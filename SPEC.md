# Pimdir store specification

Status: draft

The on-disk store for text-based personal-information items (mail, calendar events, contacts, notes, tasks…): a **SQLite database** (the queryable index and mutable state) plus a **content-addressed blob directory** (the item bodies). It keeps the scale, indexing and cross-OS uniformity of SQLite without putting large bodies inside it.

A body edit (a mutable-content item such as a CardDAV contact) writes a new blob and repoints the item: each blob is immutable, an item's current body is not.

The key words MUST, MUST NOT, SHOULD, SHOULD NOT and MAY are to be interpreted as in RFC 2119.

## Contents

The store first, then the model it holds, then the API over it.

1. [Goals and lineage](#1-goals-and-lineage)
2. [Terminology](#2-terminology)
3. [Store layout](#3-store-layout)
4. [The database](#4-the-database): [requirements](#41-requirements), [schema version](#42-schema-version), [tables](#43-tables), [queries](#44-queries)
5. [The blob store](#5-the-blob-store)
6. [Migrations](#6-migrations)
7. [Integrity](#7-integrity)
8. [Concurrency and ownership](#8-concurrency-and-ownership)
9. [Identity and dedup](#9-identity-and-dedup): [the public id](#91-the-public-id-seq), [accounts](#92-accounts), [the sort key](#93-the-sort-key)
10. [Sync model](#10-sync-model)
11. [Retention](#11-retention): [requirements](#111-requirements), [purging](#112-purging)
12. [Collection generation](#12-collection-generation)
13. [Encodings](#13-encodings)
14. [Operations](#14-operations): [reading the store](#141-reading-the-store)
15. [Action queue](#15-action-queue): [producing](#151-producing), [applying](#152-applying), [actions](#153-actions), [reading the queue](#154-reading-the-queue), [cancelling and acknowledging](#155-cancelling-and-acknowledging)
16. [Test vectors](#16-test-vectors)

[Annex A](#annex-a-application-meta-conventions-informative) holds the per-kind `meta` and `sort_key` conventions, which are informative rather than part of the format.

The sections were reordered on 2026-08-16, so a citation written before then may name a different number; [the log entry](./cairn/log/2026-08-16-spec-restructure.md) maps the old numbers onto the new ones.

## 1. Goals and lineage

Pimdir generalises what most PIM stores already do (Apple Mail, Thunderbird, notmuch, evolution-data-server): an **indexed binary store** for state and queries, the **large immutable content** beside it. Its goals, in priority order:

- **Generic**: one store for any text-based item kind, keyed by media type, not one store per domain.
- **Scalable and indexed**: hundreds of thousands of items with real secondary indexes (by link id, by flag, by object), not per-item file opens.
- **Portable**: the SQLite file format is byte-identical and endian-independent across every OS and architecture, with a stability commitment through 2050, and meets none of the case-sensitivity, forbidden-character, `MAX_PATH` or extended-attribute problems of file-per-item layouts.
- **Transactional**: a whole flag-set change or a multi-item move is one ACID commit, not a sequence of renames a reader can catch mid-flight.
- **Rebuildable, not sacred**: the database is a *derived* index over the authoritative blobs and the remote, so corruption is survivable by re-sync (§6, §7). The one exception is un-pushed local mutation, which only the database holds.

SQLite specifically, not "any SQL database": the portability comes from the file format, a single file you can copy rather than a server you must run. SQL is merely the access API, so any language with a SQLite binding can implement this.

## 2. Terminology

- **Store**: a directory holding one database file and one blob directory.
- **Database**: the SQLite file pimdir.db, holding collections, items, their per-source bindings, objects (index rows) and checkpoints.
- **Collection**: a mailbox, address book or calendar; a row in `collections`.
- **Account**: the identity a collection belongs to (a mail account, a CardDAV login). An opaque owner-chosen id in `collections.account`, `NULL` in a single-account store. It groups collections for reading and filtering, partitions no identifier, and the store never interprets it (§9.2).
- **Item**: one message, event, task or contact.
- **Placement**: one item's presence in one collection: its handle, mutable state (flags), detail level, sync base, and a pointer to its object. The same item in two collections is two placements sharing one object.
- **Object**: a content-addressed, immutable item body. Index row in `objects`, bytes in a blob file.
- **Handle**: the backend's id for a placement within its collection (an IMAP UID, a JMAP id, a server file id).
- **Link id**: the item's key in its collection, assigned from the **identity hint** the content states (`Message-ID`, vCard/iCal `UID`) and equal to that hint unless the collection already holds it (§9). Never a byte size, which drifts on per-copy header rewrites.
- **Hash**: a cryptographic content hash of an object's bytes: its integrity value, dedup key and blob filename.
- **Checkpoint**: an opaque per-source cursor recording the last point synced with the remote (QRESYNC state, JMAP state string, DAV sync-token).
- **Retained item**: an item no source holds any more, kept instead of deleted and hidden from the sync seam and the live reads until it is purged (§11).
- **Owner lock**: the exclusive advisory lock on owner.lock that makes the single-owner rule enforceable, held by the owning process for as long as it owns the store (§8).
- **Staging lock**: the advisory lock on objects.lock delimiting the window in which a body is written but not yet referenced. Producers hold it shared across that window; the collector takes it exclusively, which is how it knows no writer is inside one (§5, §8).

## 3. Store layout

A store is a directory containing exactly:

```
mystore/
  pimdir.db            the SQLite database (may be accompanied by -wal / -shm)
  owner.lock           the owner lock, held exclusively (§8)
  objects.lock         the staging lock, held shared by producers (§8)
  objects/             the content-addressed blob directory (§5)
    ab/cd/abcd…         a body, at objects/<h[0:2]>/<h[2:4]>/<hash>
```

A directory is a pimdir store if and only if it contains a pimdir.db whose `store_meta.format` is `'pimdir'`. The database *is* the marker; there is no separate marker file: the lock files are empty, created by the first handle that takes one, and hold no state of their own (§8), so a store that has only ever been read has neither.

## 4. The database

### 4.1 Requirements

- The database MUST be a SQLite database, file name pimdir.db.
- Implementations MUST require **SQLite ≥ 3.37** (2021), for `STRICT` tables and `DROP COLUMN`. All tables MUST be `STRICT`, so column types are enforced rather than left to SQLite's dynamic affinity. That is what makes the schema safe across implementations.
- `PRAGMA foreign_keys = ON` MUST be set per connection.
- For a local store, `PRAGMA journal_mode = WAL` is RECOMMENDED. For a store on a network filesystem, see §8.

### 4.2 Schema version

The schema version is held in `PRAGMA user_version` and mirrored in `store_meta.version`. The two MUST agree; an implementation opening a store where they disagree MUST treat it as corrupt.

Version 1, the current version, is [migrations/0001_init.sql](./migrations/0001_init.sql): the whole schema, action queue, retention (§11) and collection generations included. While this spec is `draft`, version 1 is **edited in place** (§6) and `user_version` stays `1`; a store stamped with any other version, or created by an earlier draft, is recreated, never migrated.

### 4.3 Tables

The canonical schema is migrations/0001_init.sql. It is normative and this section is its prose companion.

- **`store_meta`** (one row): `format`, `version`, `hash_algo` (the hash used for every object: `blake3` RECOMMENDED, or `sha256-128`, recorded here so it is discoverable and swappable by a future migration), `created_at`.
- **`collections`**: `id`, the owning `account` (§9.2), `kind` (the media type shared by every item in it), `name`, `parent` (hierarchy by reference, never by row nesting), optional presentation (`color`, `description`, `sort_order`), the cross-source `conflict` policy, and the handle-space `generation` (§12). Every foreign key onto `id` is `ON UPDATE CASCADE`, so a collection can be renamed without losing its contents (§14); `ON DELETE` stays `CASCADE` (`SET NULL` for `parent`).
- **`sources`**: one row per source syncing a collection (a server, a phone), keyed `(collection, source)`, carrying that source's opaque `checkpoint`.
- **`objects`**: `hash` (primary key, under `hash_algo`), `size`, `refcount` (§5, §7). The bytes are *not* stored here.
- **`items`**: the shared truth of one logical item, keyed `(collection, link_id)`. Carries the mutable `flags` (a JSON array), the current `object_hash`, the opaque `meta` summary, the `sort_key` ordering it within its collection (§9.3), the detail `level` (0 probed → 1 meta → 2 full), and the cross-source state `deleted` / `conflicted` / `conflict_object`.

  It also carries `seq`, the store-global **public id** a client shows in place of the internal `link_id` (§9.1), and the retention stamps `retained_at` / `retained_by` (§11), a non-`NULL` `retained_at` being the persisted form of "no source holds this any more, and the store kept it anyway". The partial index `items_retained` scopes the trash listing and the purge sweep to those rows.
- **`bindings`**: one source's binding of an item, keyed `(collection, link_id, source)`. Carries the item's `handle` on that source, the three-way-merge base (`base_flags`, `base_object`, `base_revision`), the shared body it last reconciled against (`shared_object`), and the unresolved-conflict triple `conflicted` / `conflict_revision` / `conflict_object`. The handle is bound once and never repointed (§10).

  The two bases answer different questions and a store keeps both (§10): `base_object` is what this source last agreed with its own **remote**, which is what makes a pending push derivable, and `shared_object` what it last agreed with the **hub**, which is what a cross-source divergence is measured from.
- **`queue`**: the action queue (§15). Carries the append `id`, `created_at`, the diagnostic `producer`, the target `collection`, the `action` kind, the versioned JSON `payload`, the GC-pinning `object_hash`, and the `attempts` / `error` parking state.

An item plus a base per source is the whole model: **single-source is the N=1 case**, one binding. The only thing N≥2 adds is `deleted`, a removal that must linger until every source has dropped it.

Flags are a JSON array rather than a child table: the set is small per item and `json_each` makes "all unread in a collection" an ordinary query. A consumer with heavy flag-query needs MAY build its own derived table, a private index out of scope here.

### 4.4 Queries

The named, parameterised statements servicing the operations (§14) live under queries/, one file per concern: [collections](./queries/collections.sql), [items](./queries/items.sql), [bindings](./queries/bindings.sql), [sources](./queries/sources.sql), [objects](./queries/objects.sql), [queue](./queries/queue.sql). They are the reference form, bound with the §13 encodings; an implementation SHOULD use them verbatim and MAY substitute an equivalent that preserves the same invariants (§7).

## 5. The blob store

Object bytes live under objects/, one file per hash, **sharded two levels by hash prefix** (`objects/<hash[0:2]>/<hash[2:4]>/<hash>`) to keep any one directory small. The hash is encoded in lowercase base32 (RFC 4648, no padding), so the path is valid on every target filesystem.

An **object name** is fully determined by these rules, and every part of them is normative, because a store whose two writers name the same body differently does not report a mismatch: it silently stops deduplicating and stops finding the blob the other side wrote.

- The digest is taken over the body's **raw bytes**, whole, with no length prefix, framing or transformation.
- **`blake3`** is BLAKE3 in its default 32-byte output length, giving a 52-character name. **`sha256-128`** is the **leading 16 bytes** of the SHA-256 digest, giving a 26-character name; it exists for a runtime whose standard library has SHA-256 and no BLAKE3, and truncating a digest to half its width is sound where the second preimage is not the threat. Which one a store uses is `store_meta.hash_algo` (§4.2), and it MUST NOT be inferred from a name's length.
- The alphabet is RFC 4648 **§6** (`abcdefghijklmnopqrstuvwxyz234567`), lowercased, **not** §7's base32hex, which shares the length and none of the characters. Padding is omitted (RFC 4648 §3.2), so a name carries no `=`.
- The shard directories are the first two and the next two characters **of that encoded name**, never of the digest's hex.

§16's vectors are what an implementation checks itself against; the empty body is in them, and it is a real object rather than a special case.

- **Write** is atomic: write a temporary period-prefixed file in the same shard directory, `fsync`, then `rename` into place, then **`fsync` the shard directory**. The name being the content hash, a file is never rewritten. The directory sync is not optional bookkeeping: syncing the file makes its bytes durable and says nothing about the name that reaches them, while the database commit *is* durable, so without it a power loss can leave a committed row pointing at a body that never arrived. That is the one asymmetry the write order of §14 exists to prevent, the reverse leaving at worst an orphan blob, which the collector below reclaims and nothing else does.
- **Reference counting**: `objects.refcount` MUST equal the number of pointers at that hash, counting an item's `object_hash` and `conflict_object`, a binding's `base_object` and `conflict_object`, and a queue row's `object_hash` (§15). A body waiting in the queue is pinned exactly like a referenced one, and so is the body of a retained item (§11) and the diverging body an unresolved conflict is waiting on (§13). Refcounts are maintained in the same transaction as the writes that change them.

  A binding's `shared_object` names a body and MUST NOT be counted, which is the one exception and is deliberate: it records which body a source last agreed with, is only ever compared for equality and never read as bytes, and a content hash compares the same after the body it named has been swept. Counting it would pin every body a source ever agreed with for the life of the binding.
- **An unreferenced object is not a deleted one**: an object whose refcount reaches zero is unreferenced, and it stays. A write MUST NOT delete such a row and MUST NOT unlink its blob. A consumer MAY index a body in one batch and attach it in a later one, which §14 step 1 explicitly invites for a body streamed to its sharded path without being held whole, and a sweep at the end of the first batch destroys what the second was about to reference: silently, bytes included. Reclamation is a separate operation, below.
- **The collector**: reclamation is one operation, run when it is asked for. It deletes the object rows at refcount zero and unlinks every blob file no `objects` row names: those rows' own bodies and the **orphans** a crash left, which are one case rather than two once the rows are gone. The predicate is `refcount <= 0` rather than `= 0`, which matches the partial index `objects_garbage` exactly, and the wider form is what keeps a **reader** honest: a reader opens read-only (§8), so it cannot apply §7's floor to a store written before that constraint existed, and a negative count there must still read as collectable rather than as live.

  Its statements are `list_garbage_objects` and `delete_garbage_objects` for the rows, and `object_exists` for the files: the collector walks the blob directory and asks that one about the file in front of it, on the primary key. It does **not** read `list_object_hashes` first, which would hold the whole index in memory to answer a question about one file, and which exists for the diagnosis that has to visit every row anyway (§7's missing-body check).

  The collector MUST **read the directory**, since an orphan is by construction a file the database holds no evidence of. Orphans are ordinary rather than exceptional: every crash between a commit and its unlink leaves one, and so does every body written for a batch that then failed. A store therefore needs the collector run periodically, and the format states it because a store that never runs it grows without bound and reports nothing, every check it has passing.

  Running it is the **owner's** to schedule, and the format says so because nothing else will: no write reclaims, so a store whose owner never collects keeps every dereferenced body for ever. An owner that purges (§11.2) is releasing bodies by definition and is the natural place to run it.

  The collector MUST hold the store's **exclusive owner lock** and take its **staging lock exclusively** (§8), and those two are what an earlier draft's grace period was standing in for. A body is written before the row that references it, and MAY be written before the transaction opens, so a file that has just appeared is indistinguishable by inspection from an orphan: the only question is whether a writer is in flight, and the locks answer it, where a timer only guessed at it. A period-prefixed temporary file (the write above) is not an orphan and MUST be left alone: it belongs to a writer that has not renamed it into place.

  A store MAY recompute refcounts from the pointer columns before collecting: O(placements), and immune to bookkeeping drift (§7).
- Bodies are content-addressed, so an identical body in two collections is stored once, and copy, move and undelete are pointer edits rather than byte copies.

Keeping bodies out of the database is what makes the database a *rebuildable cache* (§6): the irreplaceable data survives any index corruption.

## 6. Migrations

Schema evolution is a set of ordered, forward-only SQL scripts under migrations/, named NNNN_description.sql (zero-padded, ascending). They are canonical: every implementation applies the identical SQL behind a ~20-line runner.

The runner MUST:

1. Read `PRAGMA user_version` (0 for a fresh database).
2. For each migration numbered above the current version, in ascending order: open a transaction, execute the script, set `PRAGMA user_version` to that number, commit. A failed script MUST roll back its transaction and stop.

Migrations are **forward-only**. There are no down-migrations because the database is derived: an implementation meeting a store newer than it understands, or a corrupt one, MAY rebuild from the blob store and a full re-sync instead.

> **Caveat (normative):** the database is the only home of **un-pushed local mutation**, a change made offline and not yet synced. Rebuild-by-resync therefore MAY lose it. A migration MUST preserve item and binding state; rebuild is a last resort, not a substitute for migrating.

> **While this spec is `draft` (normative):** a schema change MAY be folded into [migrations/0001_init.sql](./migrations/0001_init.sql) in place rather than added as version 2, `user_version` staying `1`. The forward-only rule above governs every version from the first frozen one onwards.
>
> The cost is that a store created by an earlier draft is not detectably out of date: its `user_version` already matches, so the runner does nothing and the missing columns surface as query errors. An implementation servicing a draft store MUST therefore either reconcile the shape on open (`ALTER TABLE … ADD COLUMN`, idempotent when guarded by `PRAGMA table_info`) or refuse the store with a message telling the operator to recreate it. Failing a query later is not acceptable. This allowance disappears when the spec leaves `draft`.
>
> A reconciled column MUST also be **backfilled** wherever `NULL` is not the value the existing rows already imply, in the same transaction as the `ALTER TABLE`. The added column is a statement about rows that were written before it, and one whose empty value contradicts them is worse than a missing column, which at least fails visibly: `bindings.shared_object` is backfilled from its item's `object_hash` (`backfill_shared_object`), because a binding left empty reads as never having folded, the sync base stands in for it, and the first absorb after the upgrade files the source's own pending edit as a cross-source divergence (§13).
>
> A **constraint** is not reachable that way: SQLite has no `ALTER TABLE … ADD CONSTRAINT`, so reconciling one is the table rebuild (create the constrained table under a temporary name, copy, drop the old, rename), inside the same transaction as the column and index reconciliation. Four things about it are normative, because getting any of them wrong fails quietly rather than loudly:
>
> - **Repair the data first.** Existing rows are checked as they are copied, so a store carrying real drift fails the rebuild and does not open at all. For §7's floor the repair is `recompute_refcounts`, which can only write counts at or above zero, so it always terminates and the store migrates instead of refusing.
> - **`PRAGMA foreign_keys` off for the rebuild's duration**, since dropping the old table is otherwise refused by every key referencing it, and `PRAGMA foreign_key_check` before the commit, since that is what the disabled enforcement gave up.
> - **Recreate the indexes.** They belong to the dropped table and go with it, and the rename does not bring them back. One missed here raises no error, it only leaves a store that silently scans.
> - **Detect the constraint from `sqlite_schema`**, not from `PRAGMA table_info`, which reports a column's type, nullability and default and never says whether it is constrained.

## 7. Integrity

- A store is self-checking: `PRAGMA integrity_check` on the database, plus recomputing an object's hash and comparing it to its `objects.hash` and blob filename, detects corruption with no external manifest.
- The refcount invariant (§5) and the schema's foreign keys are the structural invariants; an implementation MAY verify and repair refcounts by recomputation, with `recompute_refcounts` (§14). It settles every object in one grouped pass over the five columns that pin one (an item's body, an item's conflict body, a binding's base, a binding's diverging remote body, a pending queue action's body), so it is linear in those pointers rather than in their product with the object table, and it counts zero for an object none of them names any more.
- **The refcount has a floor**: `objects.refcount` carries `CHECK (refcount >= 0)`, so the count cannot go negative at all. A double release is a bookkeeping error whose two outcomes both hide it. If a pointer remains, the collector tries to delete a row four foreign keys still reference, and its transaction fails on `FOREIGN KEY constraint failed`, naming neither the object nor the release that miscounted it, and failing the same way on every write from then on. If none remains, the collector takes the row and nothing is left to notice. The constraint moves the failure to the statement that caused it. It is checked per statement, never deferred to the commit, so a transaction cannot net a dip below zero back out: a correct batch never dips, since it releases no more pointers than the hash holds, and one that does had the error before the constraint reported it.
- The order of trust is **blob bytes > database row**. A body whose recomputed hash disagrees with its row is authoritative, and the row is repaired from it.

## 8. Concurrency and ownership

The store has a **single-owner** rule: at most one process, on one host, owns pimdir.db at a time, and only the owner mutates collections, items, bindings, sources and objects (beyond the producer upsert below).

An owner MUST take an **exclusive advisory lock** on `owner.lock`, beside pimdir.db, and hold it for as long as it owns the store. The lock belongs to the open file, not to the file's existence: the operating system releases it when the process dies, so a crashed owner leaves a lock file that locks nothing and there is nothing to recover. A lock file whose *existence* is the lock cannot say that, and the escape hatch it then needs for a stale one puts the race back.

An owner that cannot take the lock MUST fail immediately, naming the store, rather than waiting for it. The wait would have to outlast a whole sync transaction, which is a stall with no signal rather than either an answer or a failure, and what to do instead — retry, back off, queue the intent through §15, tell the user — is the calling program's to choose. The database's own busy timeout is unaffected: owners and producers still contend on the write lock, and that contention is worth waiting out.

The rule is about **processes**. An implementation opening several handles over one store, one per source or one per account, is one owner: it takes the lock once and shares it, rather than contending with itself.

That sharing is also the lock's limit, and it has to be said because §5 leans on it: **the owner lock excludes other processes and nothing inside its own.** An owner running the collector on one handle while another writes on a second is not stopped by a lock both are holding, and the collector's whole safety argument is that no writer is in flight. An owner that runs the two concurrently MUST therefore serialise them itself. Sharing the lock is what makes the acquisition and the release one operation too: an implementation that lets a handle be observed released while the file description it named is still open will refuse itself the store, reporting a conflict with no other process in it.

Two lesser roles exist beside it, both local-host only:

- **Readers** open the database read-only and see consistent WAL snapshots; any number may run concurrently, including while an owner holds the store. A reader MUST NOT take either lock.
- **Producers** request mutations without owning the store. Their only permitted write is the §15 enqueue transaction; they MUST NOT touch any other table, and MUST NOT assume when the owner will apply the action. A producer MUST take a **shared advisory lock** on `objects.lock` across the blob write and the enqueue that pins it (§15.1), and hold it until both are done. Any number of producers hold it at once, and it is deliberately not the owner's lock: producers exist to append while the owner syncs. What it delimits is the one window in which a body is written but not yet referenced, which is the window a collector must not run inside.

On a **network filesystem** (NFS/SMB), neither SQLite's cross-host locking nor the advisory locks above are reliable, so a store on a share MUST be owned by exactly one process on one host, typically a front daemon clients talk to rather than opening the file themselves. Two owners MUST NOT run, and an implementation SHOULD enforce single-instance with a lease. Such an owner MUST NOT rely on WAL's shared-memory (`-shm`) file or on `mmap`, both of which assume a local filesystem: it MUST use rollback-journal mode or `PRAGMA locking_mode = EXCLUSIVE`.

Because writes are transactional, a reconciled flag set or a multi-item move commits atomically, and a reader never observes a torn change.

## 9. Identity and dedup

Four identifiers, kept distinct:

- **handle**: the backend's per-collection id (IMAP UID, DAV href). It changes if the backend reassigns it, so it is never the cross-collection key.
- **link id**: the item's key in its collection (`items.link_id`), assigned from the **identity hint** the content states (a bare `Message-ID`, a vCard or iCalendar `UID`, per kind in Annex A) and equal to that hint in every ordinary case. **Internal**: a consumer keys reads and edits by `seq`.
- **hash**: content state and blob key; changes when the content changes (mutable-content backends only, mail bodies being immutable).
- **seq**: the store-global **public id** (`items.seq`), a small integer a consumer shows in place of the long link id, the same in every collection the item is filed in (§9.1).

**Annex A derives the hint, this section assigns the key.** The two are the same string until one collection holds one hint twice, which a server hands over however firmly its protocol forbids it (§A.3). A writer resolving an item's identity in a collection SHALL assign its `link_id` from the first of these that applies:

- the content states **no usable hint**: the kind's fallback, unchanged, a writer-derived id under the kind's prefix (`alt:` for a message, `hash:` for a DAV resource);
- the hint is **free in this collection**: the hint verbatim, which is every item written before this rule and all but a handful after it;
- the hint is already carried by an item **this source binds under a different handle**: a **minted** key, the four parts `dup:`, the hint, `#` and that handle, concatenated verbatim in that order and nothing else (`dup:abc@host#1174`, `dup:event-1@example.org#event-1%2540example.org.ics`).

The minted form carries no digest, so whatever mints it depends on nothing that hashes; it is deterministic, so a store rebuilt from the same collection mints the same key; and it is prefixed like the kind fallbacks, so the rule that a prefixed id is never pushed as a protocol `UID` covers it with no new case. It is **opaque**: a reader MUST NOT parse it and a store MUST NOT re-canonicalise one, so a minted item keeps its key for ever, the deletion of the copy holding the bare hint included. Rewriting it would change a `seq` a consumer has already shown (§9.1).

Deduplication keys on equal **hash**, so a message filed in two mailboxes, or a body another collection already fetched, is stored once and opening it costs no network. Merging keys on the **hint**, conservatively: a missed dedup is harmless, a wrong merge hides data. The key is neither of those two, and the asymmetry is deliberate: `lookup_objects` (§14) is keyed on the assigned `link_id`, so a minted item finds no body there and fetches its own, which is a missed dedup rather than a wrong merge.

All four are store-wide, and stay so when one store holds several accounts (§9.2). An identity or a body occurring in more than one collection or account is a fact the store reports (`list_link_placements`, `list_object_placements`, §14.1) rather than a merge it performs.

### 9.1 The public id (`seq`)

`link_id` is the right internal key and the wrong thing to show a user. Each item therefore carries a `seq`, a small integer a consumer displays and accepts wherever it would otherwise take a link id. It is a property of the item, not of a placement:

- **One id per link id, store-global.** The same `link_id` keeps the same `seq` in every collection it is filed in, drawn from one store-wide counter (`store_meta.next_seq`), so a merged view shows the item once and ids never clash between collections. This holds across accounts too (§9.2): equal link ids share a `seq` wherever they sit, which reports their equality without asserting the placements are one thing.
- **Assigned once, monotonic, never reused.** The store assigns a `seq` the first time it inserts an item with that `link_id`, in any collection, and reuses it afterwards (`seq_for_link_any` finds an existing one, `bump_next_seq` draws the next). The counter only increases, so a stale id never silently addresses a different item.
- **Resolved back to `link_id`.** A consumer reads and edits by `(collection, seq)`, which is unique, and the store maps it to the link id internally.
- **A minted key is a different item.** A copy filed under a minted `link_id` (§9) draws its own `seq`, `seq_for_link_any` finding none for a key nothing else holds, and the copy holding the bare hint keeps the store-global one it already had. The cross-collection guarantee is therefore unchanged: one message filed in two mailboxes still shows once in a merged view, and what shows twice is two resources one collection genuinely holds.

### 9.2 Accounts

One store MAY hold the collections of several accounts. `collections.account` carries an opaque, owner-chosen id (an address, a config name), `NULL` in a single-account store, which is the shape everything below degenerates to.

**What the column is.** A grouping key, not an addressing one. `collections.id` stays unique store-wide, so an owner filing two accounts in one store namespaces their collection ids (`work/INBOX`, `home/INBOX`) exactly as it would have without the column. Its job is to make the grouping an indexed `WHERE` rather than a prefix match a reader has to know the owner's naming convention to perform.

**What it scopes: nothing.** Link ids, hashes and `seq`s keep the meaning §9 gives them, store-wide, whatever account a collection belongs to. The same `link_id` in two accounts is two placements sharing one `seq`; the same body is one object with two placements, refcounted twice (§5). Bodies carry no account, so dedup never did.

**What multiplicity means is the interface's job.** The store's contract is to make it visible through `list_link_placements` and `list_object_placements` (§14.1). A mail view lists the placements, because two receipts of a newsletter have two read states; a contact view may offer to merge them, because one person in two address books is usually one person. Neither is baked in, so a kind this spec has not anticipated is not pre-judged. It is the same discipline as `kind` being declared rather than derived (§14) and `meta` staying opaque.

**What the account does not change.**

- **Ownership** (§8): one store still has one writing owner, so an owner wanting to sync accounts in parallel processes MUST give each account its own store.
- **Sources** (§10), keyed `(collection, source)` and therefore already inside one account.
- **Collision risk on `link_id`**: two unrelated servers may mint the same vCard `UID`, and those placements then share a `seq` while being different people. §9 already answers it: merging is conservative, and a consumer that cannot tolerate a false pairing compares bodies rather than identities. Minting (§9) does not touch that case either, since it separates two resources **one collection** holds under one hint, and two collections legitimately sharing a hint still share a key and a `seq`.

**Configuration lives outside.** The store records which account a collection belongs to and nothing else: no credentials, no endpoints, no display name. It therefore learns an account only through its collections, so one with no collection does not appear in a listing, and a consumer needing the full roster reads it from its own configuration. That also keeps the store from becoming a second register of what accounts exist.

**Namespacing.** An owner that prefixes its collection ids MUST keep the prefix unambiguous: the separator may appear in a collection name but not in an account id. A hierarchical name must survive (`work/[Gmail]/All Mail` is account `work`, collection `[Gmail]/All Mail`), but an account id containing the separator is ambiguous, since account `a` with collection `b/c` and account `a/b` with collection `c` spell the same string. The store neither parses nor validates the id, so an owner that namespaces MUST enforce this itself.

**Choose an account id that does not change.** An id the owner namespaces with becomes part of every collection id, so naming it after something the user can rename turns a rename into an id change for every collection (survivable through `rename_collection`, §14, but avoidable). An id generated once and kept beside the account's configuration never needs it.

### 9.3 The sort key

`link_id` and `seq` are identity, not order: a link id is a `Message-ID`, and a `seq` is allocation order. Keyed on those alone a store can be paged exhaustively but cannot answer what every reader asks: *the newest fifty messages*, *this week's events*, *contacts from A*.

Each item therefore carries a `sort_key`, one TEXT column giving its position in its collection's natural order.

- **Kind-agnostic column, kind-specific meaning.** The store defines the column, the ordering rule and the paging statements; what a key means is per kind (Annex A), since only the writer knows whether an item is ordered by a date or by a name. One column serves all of them, so a reader pages a mailbox, an address book and a calendar through the same statement.
- **Written, never derived.** The `sort_key` is written by the same writer that writes `meta`, in the same insert, and the store MUST NOT parse `meta` to obtain it. An index on `json_extract(meta, …)` would make `meta` normative JSON with a reserved key, for every kind present and future, and end the property that the store never looks inside it.
- **TEXT, and byte order is the order.** The column is compared with the default `BINARY` collation, so the writer encodes a key whose byte order is the intended order (§13). For a timestamp that means RFC 3339 in UTC at a fixed width. A name and an instant are then both just bytes that sort, which keeps the store free of type-per-kind branching.
- **`''` means unknown**, the default, so an item is orderable before it is summarised. It sorts before every real key ascending and after every real one descending, which puts an unsummarised item at the end of a newest-first mail listing and at the head of an A-to-Z contact listing. A store MUST NOT read more into `''` than that.
- **`seq` is the tiebreaker.** A key is not unique, so paging orders by `(sort_key, seq)`, which makes a page total: no item skipped or repeated across page boundaries.
- **Restatable.** `set_sort_key` re-projects a store written before its kind had a convention, or one whose convention changed, without re-fetching bodies. It is not part of the ordinary write path. It is also the seam a consumer uses while its sync engine does not yet carry the key inline, dropped once the key rides the ordinary insert.
- **Preserved by a write that does not restate it.** A `write` MUST leave an existing key alone unless it carries a new one. This is a real constraint, because the reference write is a replace-all (§14): `load_items` therefore returns `sort_key` and the replace-all carries it back, although nothing in the sync model reads it. Without that, every sync would silently reset the ordering it touched.

Paging is an index seek on `items_by_sort`, not a scan: `EXPLAIN QUERY PLAN` for a descending page reports `SEARCH items USING INDEX items_by_sort (collection=? AND (sort_key,seq)<(?,?))`. That is the point of a column over an expression on `meta`, and of a keyset cursor over `OFFSET`: the cost of a page does not grow with its depth.

A key is a *presentation* fact, not a sync one. Nothing in §10 reads it and no merge keys on it, so two stores that disagree about it still converge: a wrong key mis-sorts a list and loses nothing.

## 10. Sync model

The store is shaped for offline-first synchronisation against one or more sources. A shared item holds the merged truth; a per-source binding records the base, the last state agreed with that source. A sync layer above derives what changed locally (the item versus the base) and what changed remotely, and reconciles the two.

A binding records **two** agreement points, one per axis, and a store MUST keep both. `base_object` is the body this source last agreed with its own remote, which only a sync moves, so it stays behind while an unpushed edit waits and that gap is exactly what makes the push derivable. `shared_object` is the body it last agreed with the shared item, which every absorbed upsert moves to whatever the reconcile settled on, adopted or kept or refused. Measuring the cross-source axis from the sync base instead is a defect and not an approximation: a source's own unpushed edit leaves the same gap another source folding in leaves, so a second offline edit, or the edit resolving a conflict, reads as two sources disagreeing in a store that has one.

The detail `level` lets an item be known before its body is fetched, so enumeration stays cheap and bodies hydrate lazily. `deleted` carries a removal across sources until every one has dropped it, and the item is then **retired rather than erased** (§11). A single-source store degenerates to one binding per item.

Two content divergences are recorded, and they are **not the same fact**:

- **Cross-source** (`items.conflicted`, `items.conflict_object`): two sources edited the shared body differently. It belongs to the item, being a statement about its sources disagreeing.
- **Source-versus-its-own-remote** (`bindings.conflicted`, `bindings.conflict_revision`, `bindings.conflict_object`): one source's own three-way merge diverged from its remote and was left unresolved. It belongs to that binding, since one source can be conflicted while another is in sync. The revision and the body beside it are what let resolution happen outside the process that found the conflict, in a program holding no credentials.

A store MUST persist both independently, and neither MUST set the other. A sync layer that cannot read its unresolved conflicts back re-derives on every run the push the remote already rejected and never converges, and a client cannot tell which items need a human. A binding's conflict MUST be cleared when the sync layer writes any resolved state for it, so resolving is an ordinary edit rather than a dedicated operation, and clearing it releases the pin its `conflict_object` held.

Nothing is recorded on the **identity** axis, and one rule keeps it that way: a write resolving an existing `(collection, link_id, source)` binding to a **different handle** SHALL be refused, and the store SHALL record no trace of the incoming handle. A binding pins one `handle`, so applying such a write would repoint it from the copy it held to another, destroying the fact at that write, before any layer above could act on it. Rebinding legitimately, after a handle-space change (§12), goes through the rebuild that drops the old spine and inserts the new one, which licenses the rebind for the handle its drop names and no other.

A source holding one identity twice (a double delivery, a retried append, a restore, a migration from another provider, two resources a server let share one `UID`) never reaches that refusal, because the second copy resolves to a minted key of its own (§9) before the write. It is stored as an item beside the first, with its own binding, its own `seq`, its own body and its own place in every listing, which is what an offline replica of a collection owes the collection: what the source holds, held. Two copies of one identity is redundancy, not corruption. RFC 5322 §3.6.4 binds the generator of a `Message-ID` and says nothing about what a store may hold, and RFC 4791 §4.1, RFC 6352 §5.1 and RFC 6352 §6.3.2 bind a DAV server whose collection the store reads as it finds it. The store holds both copies and judges neither: it picks no survivor, merges nothing, deletes nothing and warns about nothing. Two items is the report.

Deriving pushes, merging and resolving conflicts belong to the sync layer, not to the store.

## 11. Retention

An item's removal from every source is not the same fact as its removal from the store. A pimdir store **retains**: when an item's last source binding vanishes, the row is stamped and kept, and only an explicit purge takes it away. A remote expunge therefore never destroys the local copy, which is what makes a store usable as a backup of a source it does not control.

Retention is the terminal state of the `deleted` memory (§10), not a second mechanism beside it. `deleted` is the *in-flight* removal (dropped here, still held elsewhere); a **retained** item is one where that propagation has finished. A retained row therefore carries `deleted = 1` and holds **no bindings**, and `retained_at` is the queryable form of exactly that.

Retention is **unconditional**: no switch, no per-store flag, no per-collection policy, because whether a removal is terminal must read identically to every process that opens the store. *How long* to keep retained items and *when* to sweep them is the owner's schedule, not the store's semantics.

### 11.1 Requirements

- **Retire, do not delete.** When an item's last source binding vanishes, the store SHALL retain the row rather than delete it, setting `retained_at` to the instant the binding went and `retained_by` to the source that retired it. The row SHALL keep its `object_hash`, so the body keeps its reference (§5) and survives garbage collection. The reference statement is `retain_item`, standing where a hard-deleting store would have issued the delete.
- **Stamped by SQLite.** `retained_at` SHALL be written by the retiring statement itself (§13), so no implementation plumbs a clock through to reach it. The *cutoff* of a time-based purge is by contrast the caller's parameter (§11.2), which keeps a purge deterministic and testable.
- **Hidden from the sync seam.** A retained row SHALL be absent from the load that feeds the merge: `load_items` filters `retained_at IS NULL`. A store that retained rows *and* returned them from `load` would re-upload every one of them on the next run, so hiding them is the condition of correctness rather than an optimisation. The sync engine publishes the matching contract (io-replica's storage spec: a removal reaches storage as a drop the storage MAY retain, and the merge reconciles only what a `load` returns). The same filter is why `delete_items` spares retained rows (§14).
- **Hidden from the read surface by default.** A retained item SHALL NOT appear in the live reads, and no new rule is needed for it: the row carries `deleted = 1` and §14.1's live-only rule already excludes it. `list_retained_page` and `count_retained` are the deliberate exception, a trash view a reader MUST present as retained.
- **Purge is the only true delete.** A row leaves the store only through `purge_item` or `purge_retained_before`. The item row goes, its bindings cascade, and the body it released is unlinked by the collector (§5) whenever that next runs, so a purge reports the rows it **removed** and never bytes: it releases a body, it does not reclaim one. A purge MUST NOT take a live item: both statements are guarded on `retained_at IS NOT NULL`.

  Both `RETURN` each removed row's `object_hash` and `conflict_object`, and the caller settles them with `release_pins` in the same transaction. The pins have to be released by whoever deletes the rows, and asking for them beforehand visits every swept row twice for an answer the delete already has.
- **A reappearing link id revives.** A link id that comes back while a retained row holds its primary key SHALL **revive** that row (`revive_item`: stamps cleared, `deleted` back to `0`) and adopt the new content, rather than conflict on the key. One branch serves both a source-side resurrection and a client `add` (§15.3). The revived row keeps its `seq` (§9.1) and whatever `object_hash`, `flags` and `meta` retention preserved, so a restore costs no network.
- **Retention is not durable state a source can observe.** `retained_by` is diagnostic and nothing keys on it. A retained item has no bindings, so it participates in no merge and pushes nothing; reviving it stages it as an ordinary local creation.

### 11.2 Purging

- **`purge_item(collection, seq)`**: one retained item by its public id, an operator emptying one thing out of the trash.
- **`purge_retained_before(cutoff)`**: every item retired before an RFC 3339 instant, store-wide, the scheduled retirement. The owner computes `cutoff` from its own retention duration and passes it in, so the store neither reads a clock nor holds the policy. Never sweeping reclaims nothing, and a cutoff of *now* reproduces the terminal-delete behaviour of a store that never retained, which is why no on/off switch is needed.

`retained_bytes()` (§14.1) reports what retention is holding, so an operator can see the cost of a policy before choosing a duration.

## 12. Collection generation

`collections.generation` is the collection's **handle-space epoch**: the owner MUST bump it (`bump_generation`), in the same transaction as the rebuild, whenever it discards and re-learns the collection's handles (an identity reset such as an IMAP UIDVALIDITY change). Readers exposing epoch-dependent protocol values derive them from it with `load_generation` (an IMAP frontend maps `generation` to the UIDVALIDITY it advertises), so "the ids you cached are void" survives the process split without a side channel.

A rebuild's write batch is what makes it one: the old spine is dropped and the same items are upserted under their new handles, so a binding's `handle` **does** move, which is the one case §10's rule against repointing does not cover. An implementation persisting the batch as a diff cannot tell the two apart from the rows alone, since a rebuilt spine and a source reporting one identity under a second handle produce the same before and after. What separates them is the drop: a rebuild supersedes a handle, a removal deletes one, and only the first licenses the rebind, for the handle it names and no other. Reading it as a duplicate instead refuses the write for every item of the collection, under handles the server has just voided.

Ordinary syncs, full resyncs from an expired checkpoint, and content changes MUST NOT bump it.

## 13. Encodings

Two implementations produce byte-identical stores only if they encode the model into columns identically. These rules are normative.

- **`level`** (INTEGER): `0` probed, `1` meta, `2` full.
- **`deleted` / `conflicted`** (INTEGER): `0` or `1`.
- **`conflict`** (TEXT): the collection's cross-source content-conflict policy: `'manual'`, `'prefer-incoming'` or `'prefer-existing'`.
- **`flags` / `base_flags`** (TEXT): a JSON array of the raw flag strings, sorted ascending by code point so the encoding is canonical (e.g. `["$flagged","\\Seen"]`). `NULL` means *unknown* (not yet fetched), `'[]'` means *known-empty*; the two are distinct.
- **`object_hash` / `base_object` / `conflict_object`** (TEXT): a content hash under `store_meta.hash_algo`, base32, or `NULL`.
- **`refcount`** (INTEGER, on an object): the number of pointers at that hash, counted across an item's `object_hash`, an item's `conflict_object`, a binding's `base_object`, a binding's `conflict_object` and a queue row's `object_hash` (§5). It is constrained `>= 0` and the constraint is normative, not defensive: a count below zero is a bookkeeping error the store cannot report any other way (§7). `0` is meaningful and not a sentinel, being an indexed body no pointer names yet or none names any more, which is exactly what the collector takes.
- **`link_id`** (TEXT): the key an item is filed under in its collection (§9): the identity hint verbatim, the kind's fallback for content stating none, or a minted `dup:<hint>#<handle>` for a hint the collection already holds. Opaque, so the store never parses one and never rewrites one.
- **`meta`** (TEXT): an opaque application-defined summary blob, or `NULL` until a `Meta` fetch. The store never parses it.
- **`sort_key`** (TEXT): the item's position in its collection's natural order (§9.3), written beside `meta` and never derived by the store. `''` means *unknown*, and is the default. Ordering is the default `BINARY` collation, so a writer MUST encode the key so that byte order **is** the intended order: a timestamp as RFC 3339 in UTC at a fixed width (`2026-08-01T10:00:00Z`), never a local offset, since `+02:00` and `Z` sort apart while naming the same instant.

  It is also the one column exempt from the byte-identical rule above: a key derived from a zoned timestamp resolves through a time zone database, so two correct writers on different tzdb versions may write different keys. §9.3 is what makes that harmless: a key is a presentation fact, and a wrong one mis-sorts a list and loses nothing.
- **`base_revision`** (TEXT): an opaque etag/modseq for mutable-content backends, or `NULL`.
- **`conflicted`** (INTEGER, on a binding): whether *this source* and its own remote diverged and were left unresolved. Distinct from `items.conflicted` (§10).
- **`conflict_revision`** (TEXT): the remote revision observed when the binding was marked conflicted, or `NULL`. A binding that is not conflicted MUST NOT carry one, so a resolved binding cannot hand a stale revision to the next sync.
- **`conflict_object`** (TEXT, on a binding): the diverging remote body at `conflict_revision`, or `NULL` while it has not been fetched. It is a reference like any other, counted in the refcount above and therefore kept out of the collector for as long as the binding stays conflicted, which is the interval between the run that found the divergence and the day a person sits down to it. A binding that is not conflicted MUST NOT carry one, on the same terms as the revision beside it: a body outliving its revision describes a version the remote no longer holds.
- **`shared_object`** (TEXT, on a binding): the shared body this source last reconciled against (§10), or `NULL` until it has folded once, where the sync base stands in for it. It is meaningful whether or not the binding is conflicted, unlike the two columns above, since it describes the ordinary state of an ordinary binding: gated on the flag it would be erased at the moment the edit resolving a conflict needs it. It names an object and MUST NOT be counted in the refcount above (§5), being compared for equality and never read as bytes.
- **`created_at`** (TEXT, on `store_meta` and on `queue`): the RFC 3339 instant the row was written, in the same form and by the same rule as `retained_at` below: `strftime('%Y-%m-%dT%H:%M:%fZ','now')`, stamped by SQLite. RFC 3339 alone is not a shape, since it admits any offset and any sub-second precision, so three conformant writers produce three strings that do not sort together. `enqueue_action` stamps the queue's; `store_meta`'s is covered by no canonical statement, so whoever creates the store writes that expression itself.
- **`retained_at`** (TEXT):
 the RFC 3339 instant the item's last source binding vanished, or `NULL` while it is live (§11). It is stamped by SQLite itself (`strftime('%Y-%m-%dT%H:%M:%fZ','now')`) in the retiring update, so every implementation writes the same shape and none plumbs a clock through to reach it. It records when the last binding *went*, not when a source deleted the item, which is unknowable; a revive clears it.
- **`retained_by`** (TEXT): the source whose removal retired the item, or `NULL`. Diagnostic only.
- **`checkpoint`** (BLOB): opaque sync-cursor bytes, or `NULL`.
- **`base_present`** (INTEGER, on a binding): whether the binding has a base at all. Its three value columns cannot say: a source reporting no revision, no body and markers nobody has read still *agreed* with the placement, and that agreement is what tells a pending push from a settled one. Inferring presence from the three loses exactly that shape, and the placement then reads as never-agreed for ever, the sync re-deriving the same push on every run. A base is present iff `base_present` is 1, **or** at least one of `base_flags`, `base_object`, `base_revision` is non-`NULL`: the second clause is only for a row written before this column existed, where those values are the sole evidence there is. A writer MUST set the column; a reader MUST accept either witness.
- **`action`** (TEXT): the action kind. The kinds this format defines are `'add'`, `'set-flags'`, `'remove'`, `'move'`, `'copy'` and `'update'` (§15.3); the column is open, and an owner that does not know a kind skips it rather than parking it (§15.2).
- **`payload`** (TEXT): versioned JSON, shape per action kind (§15), leading integer `v`.
- **`error`** (TEXT): `NULL` while an action is pending; non-`NULL` records the failure that parked it.
- **`generation`** (INTEGER): the collection's handle-space epoch, starting at 1 (§12).

## 14. Operations

The operations are serviced by the canonical statements under queries/ (§4.4), bound with the §13 encodings. The statements are the reference form; §7's invariants are what bind, and an implementation MAY use an equivalent.

A store is opened *as one source*. `load` projects the collection's shared items into the placements this source holds, and `write` folds this source's changes back.

- **`load(collection)`** reads the shared items and bindings (`load_items` + `load_bindings`, with `load_conflict`), projects them for this source, and reads its `load_checkpoint`. Freshly probed placements have no link id to key an item on, so an implementation holds them aside (in memory, or a residual table) until a `Meta` upgrade links them.
- **`lookup_objects(links)`** runs `lookup_objects` with `:links` bound to a JSON array of link-id strings, and `:account` bound to the caller's own account (§9.2). The scope is deliberate: across collections the answer is what the read exists for, one message filed in two mailboxes being one body downloaded once, while across accounts a link id is not a fact at all, since two unrelated servers may mint the same vCard `UID`. Answering across accounts hands one account's body to the other's sync, which then believes the item is hydrated and never fetches the real one. A single-account store writes no account, so the filter is a no-op there.
- **`write(ops)`** runs as **one transaction**:
  1. A `StoreObject` carries the object's index row and, **optionally, its bytes**. Carrying bytes, the writer writes them to the blob file first (temporary file → `fsync` → `rename`, §5), then runs `store_object`. Carrying none, the body is already durable at its sharded path, streamed there by a consumer that fetched it without holding it whole, and whoever emits a byteless `StoreObject` MUST have completed that write first. Either form lands the object before the placement referencing it.

     The blob write MAY happen **before** `BEGIN`, and an implementation writing bodies of any size SHOULD do so. A body is content-addressed and immutable, so writing it early can only ever produce a file some later batch also produces identically, and the worst a crash between the two leaves is an orphan blob, which §5's collector exists for. Inside the transaction the same write holds SQLite's write lock across a file write, two `fsync`s and a rename, serialising every other writer behind an I/O path that touches no database page. Between the early blob write and the commit the file is on disk with no row, and indistinguishable from an orphan by inspection; what keeps a collector out of that window is the writer's lock (§8), not the file's age.

     A `SetCheckpoint` runs `ensure_collection` then `upsert_checkpoint` for this source.

     Placement upserts and drops are merged into the shared items and bindings, and the merged result is persisted, `set_conflict` carrying the collection's policy. The reference form is a load-all / replace-all per touched collection (`retain_item` for every item the result no longer holds, then `delete_items`, then `insert_item` / `insert_binding`). An implementation MAY instead persist the diff, with `update_binding` for a binding whose base or conflict moved: §4.4 permits it because the persisted state is identical. `update_binding` carries no `handle` and cannot: a write resolving an existing binding to a different handle is refused (§10), and the one rebind the format licenses is §12's rebuild, which drops the binding and inserts it under the new handle.

     An implementation persisting the diff SHOULD also **read** by the batch rather than by the collection: `load_items_by_link` and `load_bindings_by_link` bound to the link ids the batch names, resolving each dropped handle to its link id with `link_for_handle` first. The batch only ever produces writes for the items it names, so the rest of the collection is read and merged to conclude that nothing changed, and that read, not the writes, is what a small write actually costs: it grows with the mailbox instead of with the batch. Measured on the reference implementation, one flag on one message went from 3.5 ms at a thousand items and 59 ms at sixteen thousand, cleanly linear, to a flat 150 to 175 µs across the same range.

     An item the merge leaves with no binding at all is **retained, not deleted** (§11). Both forms agree on it: `delete_items` spares retained rows and `load_items` never returns one, so a retained item is outside the replace-all cycle and a reappearing link id revives its row rather than colliding with it.
  2. Bring the refcount of every object the batch touched back in line with the §5 invariant, in the same transaction. The reference form is `recompute_refcounts`, one grouped pass over the five pointer columns, O(items+bindings+queue). That cost is the *store's*, not the batch's, and it is paid whole on a write of one flag, so an implementation MAY instead adjust each affected hash by the batch's net change (`adjust_refcount`, O(changes)) and keep the recompute for the repair §7 describes.
  3. Commit. The batch reclaims nothing: an object it left at refcount zero is unreferenced, not deleted (§5), and a body it stops referencing outlives it.

An implementation MAY skip the refcount step on a batch that stored or dropped no objects.

Three further operations belong to the §15 queue: **`enqueue(collection, action, payload)`**, **`drain(collection)`** and **`cancel(id)`** (§15.5). Retention adds **`purge(collection, seq)`** and **`purge_retained_before(cutoff)`** (§11.2), both owner writes, and both report the rows they removed rather than bytes: the bytes are the collector's to report, since it is what frees them.

**`collect_garbage()`** is that collector (§5): an owner operation, holding the owner lock it already has and taking the staging lock exclusively, deleting the unreferenced rows in one transaction and unlinking the files after it, in the order every write uses for the same reason. It reports the rows it dropped, the files it unlinked and the bytes they freed.

A collection's `kind` is **declared, never derived**: which media type a collection holds is configuration, not something a sync layer can infer from what it pulls. Whoever configures the store declares it with **`set_collection_kind(collection, account, kind)`**, out of band from `write`, and any process reads it back with `load_kind`. The lazy path a write runs to guarantee its foreign-key target, `ensure_collection`, inserts an empty kind and MUST NOT overwrite a declared one, so either may run first. An empty `kind` means "created by a sync, never declared", which is distinct from a collection the store has never seen.

The `account` (§9.2) is configuration in the same sense, and both creation paths bind it without overwriting, so a collection cannot change accounts as a side effect of a sync declaring its media type. Re-accounting is the deliberate **`set_collection_account(collection, account)`**, and because the account partitions no identifier it disturbs nothing. `load_account` reads it back, which is what a scoped `lookup_objects` binds.

**Renaming a collection** is **`rename_collection(collection, new_id)`**, the *only* safe way to change an id. Every foreign key onto `collections(id)` is `ON UPDATE CASCADE`, so items, bindings, sources, queue rows and child collections follow the id in the same statement. Deleting the row and recreating it under the new id is destructive and silently so: `ON DELETE CASCADE` takes every item and binding with it, turning a rename into a full re-download and discarding staged local changes. A bare `UPDATE` is refused instead, since dependent rows default to `NO ACTION`.

Two things make an id change: a server renaming the collection (an IMAP `RENAME`, a DAV move), and an owner renaming an account it namespaced its collection ids with (§9.2). An account rename is therefore one `rename_collection` per collection plus `set_collection_account`, run in one transaction so the account moves atomically.

The cascade is required on **two** foreign keys. `collections(id)` is the obvious parent, but `items(collection, link_id)` is also one, of `bindings`, and cascading the first changes `items.collection`, which the second refuses under `NO ACTION`. This is also the one operation where `PRAGMA foreign_keys = ON` (§4.1) stops being hygiene and becomes correctness: with foreign keys off the rename succeeds and cascades nothing, leaving every dependent row pointing at an id that no longer exists. A refusal is recoverable; silent orphaning is not.

### 14.1 Reading the store

The operations above serve the **owner**. A **reader** (§8) opens the database read-only and projects it as a local backend. These reads are kind-agnostic and keyed by the public `seq` (§9.1), never by `link_id`. Each is named after the statement that services it (§4.4).

- **`list_collections()`** returns every collection with its `account`, display metadata and `generation`, ordered by `sort_order` then `id`.
- **`list_collections_by_account(account)`** returns one account's collections, the filter axis of a merged view; binding `NULL` selects a single-account store's.
- **`list_accounts()`** returns the accounts owning at least one collection. This is not a configured roster (§9.2).
- **`list_items_page(collection, after, limit)`** returns a keyset page of live items **in link-id order**, `:after` being the exclusive lower bound on `link_id` and the empty string starting from the beginning. It is the page for a sweep that must see every item exactly once (an export, a re-projection); a reader presenting a list wants one of the two below.
- **`list_items_page_asc(collection, after_key, after_seq, limit)`** and **`list_items_page_desc(...)`** return a keyset page in the collection's natural order (§9.3). The cursor is `(sort_key, seq)`, since a key is not unique and `seq` is what makes the page total. An implementation SHOULD expose the first page as "no cursor" rather than have a caller invent a sentinel.
- **`get_item(collection, seq)`** returns one live item, **`count_items(collection)`** counts them.
- **`seq_by_link(collection, link_id)`** resolves the public id of an item whose link id the caller already holds, typically one it just staged through the queue.
- **`list_link_placements(link_id)`** returns every live placement of one `link_id` with its collection and account, and **`list_object_placements(hash)`** does the same by body, pairing placements two servers gave different link ids (§9.2). The first pairs by key rather than by hint, so a minted copy (§9) is not listed beside the item holding the bare hint, and the body read is what pairs the two whenever their bytes agree.
- **`list_retained_page(collection, after, limit)`** returns a keyset page of **retained** items (§11), the live shape plus `retained_at`, `retained_by` and the body's `size`. Its `:after` is the exclusive lower bound on **`seq`**, not on `link_id`, with `0` starting from the beginning. It is a listing a reader presents, so its cursor is the public id the reader already speaks, where `list_items_page` above is the sweep read whose arbitrary total order is the point. **`count_retained(collection)`** counts them.
- **`retained_bytes()`** totals, store-wide, the size of the distinct bodies retained items hold: an upper bound on what a full purge followed by a collection would reclaim, since a body a live item also points at survives both (§5).
- **`list_sources()`** returns the distinct source names the store has synced, so a producer can discover which source to attribute its writes to.
- **`list_conflicted_bindings(account)`** returns the bindings waiting for a decision (§13) across that account's collections, `NULL` covering a single-account store, each named by its collection, link id, source and handle and carrying the three body hashes the divergence is between. A store MUST answer it without paging its collections: a run reports the outstanding count on every invocation and a listing command asks the same question directly, so the flag is filtered on rather than read back row by row.
- **`load_kind(collection)`** returns the declared media type, empty when a sync created the row without one.

Three rules bind every read:

- **Live only.** A tombstone (`deleted = 1`) is the sync layer's memory of a removal, not an item, and a reader MUST NOT present one as live. A retained item is a tombstone by that same rule; the three retained reads are the deliberate exception, and a reader surfacing their rows MUST present them as retained.
- **Level-aware.** An item is projectable before its body exists: `level` says whether it is probed, summarised or full. A reader renders a list from `meta` and MUST treat an absent body as not yet hydrated rather than as an error or a missing item, hydrating being the owner's job.
- **Snapshot-consistent.** A reader sees a consistent WAL snapshot and may run concurrently with the owner (§8).

A reader detects change cheaply by polling `PRAGMA data_version`, which moves whenever another connection commits, and MAY overlay the collection's pending actions for read-your-writes (§15.4).

## 15. Action queue

The single-owner rule (§8) leaves every other process unable to mutate, yet frontends legitimately originate mutations: a submission daemon queuing a send, a server frontend flipping a flag, a client filing an item. The `queue` table is their write door: a **producer** appends an action, the **owner** applies it.

The queue is domain-generic, addressing collections and public ids rather than protocol concepts, so the six kinds this format defines serve mail, contacts and calendars alike. The kind is an open string beside a versioned payload (§15.3), so one queue also carries an application's own intents, which owners that cannot perform them pass over (§15.2).

### 15.1 Producing

A producer enqueues in **one transaction**: `ensure_collection`, then, when the payload references a body, at most one `store_object` upsert (the blob file having been written durably first, §5), then one `enqueue_action` insert carrying that hash in `object_hash` so the pending body is pinned (§5). The producer passes no timestamp: `created_at` is stamped by the statement (§13), so a producer clock is never consulted and every row of the queue is stamped by one clock. This is the only write a non-owner may perform (§8). How the producer nudges the owner to run is out of scope, and a producer MUST NOT rely on any application deadline.

### 15.2 Applying

The owner drains each collection's pending actions in ascending `id`, finding which collections have any with `list_queued_collections`. An action is applied to the items and bindings and its row deleted **in the same transaction**, so application is exactly-once and never partially visible; because applying is a pure store mutation, that transaction never spans network I/O.

The delete is `claim_action`, and it runs **first** in that transaction, not last. `load_pending_actions` is read outside any transaction, so a second owner may hold the same list: deleting at the end has both apply the row, and `add` and `copy` are not idempotent. Claiming it first makes exactly-once a property of the statement rather than a convention about who runs the drain, and it is what §8's advisory lock would otherwise be load-bearing for. A claim that deletes no row means another owner got there first, and there is nothing left to apply: the transaction ends without touching anything.

An action that fails is retried (`bump_attempts`, leaving the row pending). One the owner judges permanently unappliable is **parked** (`park_action`): `error` is set, the action skipped, later actions proceeding. Parked actions are left for operators, who read them back store-wide with `load_parked_actions`, and the owner MUST NOT delete them silently.

**Skipping is not parking.** Kinds are extensible (§15.3), so one queue legitimately holds store mutations any owner can apply beside capability-bound intents only a particular process can perform (a mail submission needs a send channel this format knows nothing about). An owner that does not recognise a kind, **or recognises it but lacks the capability**, SHALL skip the row: it stays pending, untouched, `error` still `NULL`, and the owner MUST NOT park it, since parking asserts a permanence that is false about work another process will do. A skipped action MUST NOT block later actions and its `attempts` SHOULD NOT be bumped, a skip being no attempt. The row keeps its `id`, so the owner that can perform it still sees it in append order.

A drain therefore has three outcomes per row: applied, parked and skipped.

### 15.3 Actions

The format carries two things about an action: a **kind** and a **versioned JSON payload**, one shape per kind. Existing items are addressed by their public id `seq` (§9.1). At `v: 1`:

- **`add`**: `{ "v": 1, "link_id": …?, "flags": […], "object": hash?, "meta": {…}?, "handle": …? }`. Creates an item, staged as a local creation for the sync layer to push; `object` matches the row's `object_hash`. A duplicate `link_id` parks the action **unless the row holding it is retained**, in which case the action revives it (§11), so restoring needs no action kind of its own. Parking is the opposite answer to §9's minting, and deliberately: reading a source means taking the collection it actually holds, so a hint another item already carries is minted a key and stored, while authoring locally means a producer named a key the collection already holds and got it wrong, which is worth telling it about rather than filing under a key it never asked for. The store is liberal in what it accepts from a source and strict in what a producer may create.
- **`set-flags`**: `{ "v": 1, "seq": n, "flags": […] }`. Replaces the flag set, absolute rather than a delta, so reapplication is idempotent.
- **`remove`**: `{ "v": 1, "seq": n }`. Removes the item from the collection; already-absent is success.
- **`move`**: `{ "v": 1, "seq": n, "to": collection }`. Refiles the item; `copy` is the same shape without the removal.
- **`update`**: `{ "v": 1, "seq": n, "object": hash, "meta": {…}? }`. Repoints a mutable-content item's body.

These six are the kinds the format *defines*, not the kinds it permits: `action` is an open string (§13) and `payload` is JSON the store never parses, so an application MAY carry a kind of its own, versioned the same way. A mail submission is the worked example, defined by the tool that can actually send. The store owes such a row exactly what it owes any other: append order, blob pinning, and the §15.2 skip rule.

### 15.4 Reading the queue

Readers MAY overlay a collection's pending actions on their projection (`load_pending_actions`) for read-your-writes, so a just-queued send shows as pending before the owner has applied it. Change is detected by polling `PRAGMA data_version`.

### 15.5 Cancelling and acknowledging

A pending or parked row MAY be removed **by request** (`cancel_action`): an operator withdrawing an action, or the process that carried out a capability-bound intent acknowledging it is done. Without it a queued action is unretractable, since only the apply path deletes a row.

- The delete SHALL run in one transaction with the refcount settle (§14), so the row's `object_hash` pin is released in the same commit and an unreferenced body falls to the collector (§5).
- Cancelling is an owner write (§8), so a producer wanting to withdraw an action asks the process holding the owner role.
- Cancelling an already-applied action is impossible by construction: application deletes the row with its effects (§15.2), so an id is either queued or gone.
- Acknowledging is the same delete from the performer's side. An intent whose effect is not a store mutation is therefore **at-least-once**: a crash between the effect and the commit leaves the row pending and it is performed again. Deduplicating, where it matters, is the performer's job.

## 16. Test vectors

The schema is checkable: an implementation can compare its tables against migrations/0001_init.sql through SQLite's own pragmas, and a missing column or a wrong foreign-key action fails. Every *value* this format fixes was checkable by nobody, and that gap has a shape worth stating, because it is not the shape a mismatch usually has.

A store whose two writers name the same body differently **reports nothing**. It does not error, it does not warn, and no read returns a wrong answer. It silently never deduplicates, and silently never finds the blob the other side wrote. The same is true of a `meta` field spelled differently and of a `sort_key` derived differently: the list is merely emptier, or in the wrong order, and no process is in a position to notice. Prose cannot close that, because two readers of the same prose are exactly what produced it.

**vectors/** is therefore part of the format, alongside migrations/ and queries/. It holds the values every implementation must agree on, as data:

- **vectors/objects.json**: bodies to object names under both `hash_algo` values, with the shard path §5 derives from each, and the RFC 4648 §10 encoding vectors the names are built on.
- **vectors/meta.json** and **vectors/fixtures/**: bodies to the `link_id`, `meta` and `sort_key` Annex A's conventions produce, including the cases that annex has to hedge, and the minted `link_id` §9 assigns to a body whose hint the collection already holds.

Three rules bind:

- An implementation **MUST** pass vectors/objects.json. Object naming is the one place a disagreement destroys data rather than presentation: two stores that name bodies differently cannot share a blob directory, and a store re-opened by the other implementation re-downloads every body it already holds.
- An implementation **SHOULD** pass vectors/meta.json for each `kind` it writes. These follow Annex A, which is informative, so the vectors bind an implementation to the conventions it claims to implement rather than to conventions it does not. Its minted cases are the exception, restating §9 rather than a convention: an implementation that mints a key at all **MUST** mint the one they give, since two implementations minting differently file the same second copy under two keys and neither can read the other's store.
- A consumer **MUST** compare parsed structures, never JSON text. Key order is not fixed here, and pinning one would pin an accident of whichever serialiser wrote the file rather than a rule of the format.

The expected values are authored from the algorithm and prose specifications rather than produced by running an implementation, so that no implementation is the reference and two can genuinely disagree with the file rather than agreeing with each other. Each file records how its values were derived and what independently published vectors they were anchored to.

An implementation that cannot read vectors/ from its own build (it is not checked out beside this repository, or it builds from a package registry) MAY vendor the files, provided it records their digests and re-checks them against this repository in CI. Vendoring without that check is worse than not vendoring: it turns a moving format into a frozen copy that keeps passing.

## Annex A. Application meta conventions (informative)

The store never parses `meta` (§13), but the *writer* of a collection and its *readers* must agree on its shape per `kind`, so a reader can display an item without fetching its body. These conventions are **informative**, each JSON with a leading integer `v`. An absent optional field means "unknown".

Each kind also fixes what its `sort_key` (§9.3) holds: a separate column, agreed here for the same reason and by the same two parties.

### A.1 `message/rfc822` (`v: 1`)

```json
{
  "v": 1,
  "message_id": "abc@host",        // string, optional, bare Message-ID (no <>)
  "in_reply_to": ["def@host"],     // array of strings, optional, bare msg-ids
  "subject": "Hello",              // string, required (may be empty)
  "from": "alice@example.org",     // string, optional, first sender address
  "to": "bob@example.org",         // string, optional, first recipient address
  "date": "2026-08-01T10:00:00Z",  // string, optional, RFC 3339 in UTC
  "size": 1234                     // integer, optional, raw message octets
}
```

**Identity hint**: the bare `Message-ID` (RFC 5322 §3.6.4), its angle brackets stripped, exactly as `meta.message_id` carries it. A message stating none, or one no parser accepts, falls back to a writer-derived `alt:` id. This annex derives the hint; §9 assigns the `link_id` the item is filed under, which is the hint verbatim unless the collection already holds it under another handle.

`from` and `to` carry the **bare `addr-spec`**, the display name stripped, so `Alice Example <alice@example.org>` is written `alice@example.org`. `date` is normalised to **UTC**, like the `sort_key` below and for the same reason: a writer east of the sender and one west of it would otherwise record the same message differently, and a reader comparing two accounts would see two dates.

Flags are **not** in `meta`; they are the item's `flags` (§13). The summary is written by the sync connector on both the enumerate/`Meta` and the streamed/`Full` paths.

`in_reply_to` is the `In-Reply-To:` header (RFC 5322 §3.6.4), which the grammar makes `1*msg-id`, so it is an array even though one id is the common case. Each id is stripped of its angle brackets exactly as `message_id` is, so the two compare byte-for-byte and a reader can pair a reply with its parent without fetching either body. That pairing is the reason it is carried at all: an offline store is where a body read is most expensive, and the IMAP `ENVELOPE` a connector already fetched carries the header at no extra cost. `References:` is deliberately absent, being the field a full threading algorithm needs and the one no `ENVELOPE` returns.

**`sort_key`**: the `Date:` header, normalised to RFC 3339 in UTC at seconds precision (`2026-08-01T10:00:00Z`), so byte order is chronological order. Read descending for the usual newest-first listing. A message with no parseable date keeps `''` and lands at the end of it.

Mail is the kind where the two derivations must agree: the `Meta` path formats the envelope's date and the `Full` path the parsed body's, and a key that differs between them re-sorts the message when it is hydrated.

### A.2 `text/vcard` (`v: 1`)

```json
{
  "v": 1,
  "uid": "urn:uuid:4fbe8971-0bc3",  // string, optional, the vCard UID verbatim
  "fn": "Jane Doe",                 // string, required (may be empty), display name
  "emails": ["jane@example.org"],   // array of strings, optional, every EMAIL
  "size": 421                       // integer, optional, raw card octets
}
```

**Identity hint**: the vCard `UID` verbatim, exactly as `meta.uid` carries it; a card stating none falls back to a writer-derived `hash:` id over its bytes. This annex derives the hint; §9 assigns the key. RFC 6352 §5.1 requires that `UID` to be unique within its address book collection and §6.3.2 lets a server refuse a write that would break it, so a collection holding one `UID` twice is something the server handed over: both cards are stored (§9), and offering one back is a write the server is free to refuse.

Unlike mail, a card has **one** derivation: a CardDAV `sync-collection` REPORT returns hrefs and ETags but no `UID`, so a card resolves at `Full` only. A card carries no flags either, so its `flags` is a known-empty `'[]'` rather than `NULL`.

Cards are **mutable**, which mail is not: the same card is edited in place under a changing ETag, so its `revision` (§13) moves while its `link_id` does not.

**`sort_key`**: the display name (`fn`), normalised for ordering rather than display: lowercased by the **Unicode simple lowercase mapping**, locale-independent (never the Turkish dotless-i tailoring a default locale may apply), then leading and trailing whitespace removed. `meta.fn` keeps the `FN` value verbatim, whitespace and case included, since it is what a reader displays; only the key is normalised. Read ascending. A card with no `FN` keeps `''` and sorts to the head, where a nameless contact is visible rather than buried. Normalising is what keeps the order stable across writers, which would otherwise interleave `alice` and `Alice` differently.

### A.3 `text/calendar` (`v: 1`)

**The item is the calendar object resource, not the component.** RFC 4791 §4.1 requires the components sharing a `UID` to live in the same resource, so a recurrence set stays whole, and requires that `UID` to be unique within its collection. A recurring series and its modified instances are therefore **one** item: one blob carrying the master, every `RECURRENCE-ID` override and the `VTIMEZONE`s they reference, under one `link_id`.

An override is therefore a body edit rather than an item of its own, and the resource keeps the one href and ETag a binding records. A connector to an instance-granular source (a JSON calendar API handing each modified instance over separately) MUST reassemble the set into one resource before writing it, or two stores of the same calendar disagree about how many items it holds.

**The format does not assume the server enforced that uniqueness.** RFC 4791 §4.1 requires it of a calendar collection, as RFC 6352 §5.1 and §6.3.2 do of an address book one, and collections holding two resources under one `UID` are handed over anyway: two resources one client wrote under names differing only in an escape, a restore, a migration. `(collection, link_id)` is therefore the store's own uniqueness and not the protocol's restated (§9): the second resource is filed under a minted key and kept, where trusting the requirement stored it nowhere.

```json
{
  "v": 1,
  "uid": "event-1@example.org",       // string, optional, the iCalendar UID verbatim
  "component": "VEVENT",              // string, optional: VEVENT, VTODO or VJOURNAL
  "summary": "Stand-up",              // string, required (may be empty)
  "location": "Room 2",               // string, optional, the LOCATION verbatim
  "dtstart": "20190107T090000",       // string, optional, the value verbatim
  "dtstart_tzid": "America/New_York", // string, optional, the TZID parameter
  "dtstart_value": "date-time",       // string, optional: date-time or date
  "dtend": "20190107T093000",         // string, optional, the value verbatim
  "due": null,                        // string, optional, VTODO only; omitted, not null, on other components
  "recurring": true,                  // bool, optional: carries an RRULE or an RDATE
  "until": "20261231T235959Z",        // string, optional, the RRULE's UNTIL verbatim
  "size": 421                         // integer, optional, raw item octets
}
```

The **identity hint** is the `UID`, which identifies the same object across sources (RFC 5545 §3.8.4.7); content carrying no usable `UID` falls back to a writer-derived `hash:` id rather than being refused, and §9 turns the hint into the key the item is filed under. `component` names what a reader renders the resource as, and a resource may hold only one component type anyway (RFC 4791 §4.1, `VTIMEZONE` aside). `due` belongs to a `VTODO` alone and `dtend` to the components that have an end, both absent otherwise rather than merely unknown. The summary describes the master, the component carrying no `RECURRENCE-ID`.

Times are carried **verbatim**, with the `TZID` parameter and the `VALUE` type beside them, rather than as resolved instants. A reader holding a time zone database re-derives an instant in its own zone without fetching the body, and one holding none displays the wall time the calendar wrote instead of a UTC claim a writer fabricated. The single resolved projection is the `sort_key` below, so the store never carries two answers to the same question.

Like a card, a calendar object is **mutable**, so its `revision` moves while its `link_id` does not, and it carries no flags, so its `flags` is `'[]'`.

**`sort_key`**: the item's start, normalised to RFC 3339 in UTC at seconds precision (`2026-08-14T09:00:00Z`), read ascending for a chronological agenda. Which property that is depends on the component: `DTSTART` for a `VEVENT` or a `VJOURNAL`, and `DUE` then `DTSTART` for a `VTODO`, which is scheduled by its due date (RFC 5545 §3.8.2.3) and need not carry a `DTSTART` at all.

Only one of the shapes a start may take (RFC 5545 §3.3.4, §3.3.5) is an instant already, so the others normalise by convention:

- a **UTC** date-time is taken verbatim;
- a **zoned** date-time resolves through its `VTIMEZONE`, since a local time at a transition names two instants or none. When the local time is **ambiguous** (the hour a fall-back repeats) it takes the offset in effect *before* the transition, which is the earlier of the two instants; note that this is the numerically *greater* offset, so "earlier" is about the instant and never about the number. When the local time **does not exist** (the hour a spring-forward skips) it takes the offset in effect *after* the transition;
- a zoned date-time whose zone **will not resolve** (no `VTIMEZONE`, an unknown `TZID`) is read as floating rather than left unknown: the error is bounded by the offset, where dropping the key moves the item to the far end of the listing;
- a **date-only** value is read as `T00:00:00Z`;
- a **floating** date-time has its wall time read as UTC.

The last three are conventions rather than facts, the date-only case visibly so: an all-day item on the 11th sorts before an 08:00 item for a reader east of UTC and after it for one west, and the writer cannot know the reader's zone. An item with nothing parseable keeps `''` and lands at the head of an ascending listing.

A recurring item keys on its **first** occurrence, which is what `DTSTART` holds (RFC 5545 §3.8.2.4) and is fixed for the life of the series. A date-range read over recurring items therefore needs the recurrence expanded above the store, since expansion is a function of when you ask and no stored column answers it. That keeps the key deterministic and stable, and leaves time-dependence to the layer that has a clock.

`recurring` is written by any writer that parsed the body, as `true` or `false`; a writer leaves it out only when it did not look, which is what "absent means unknown" covers. It is the one optional field here whose `false` is worth writing, because a reader planning an expansion needs to tell "no rule" from "not examined".

`until` is what makes that expansion affordable. It carries the `UNTIL` of the `RRULE` verbatim, so `dtstart` and `until` bound the whole series and a reader can drop an item from a date range without materialising a single occurrence. Absent means the bound is unknown rather than absent: a rule bounded by `COUNT` states no `UNTIL`, and an unbounded one has none to state, so a reader that finds none expands to decide.
