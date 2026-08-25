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
- **Link id**: the item's cross-collection identity (`Message-ID`, vCard/iCal `UID`), the dedup and threading key. Never a byte size, which drifts on per-copy header rewrites.
- **Hash**: a cryptographic content hash of an object's bytes: its integrity value, dedup key and blob filename.
- **Checkpoint**: an opaque per-source cursor recording the last point synced with the remote (QRESYNC state, JMAP state string, DAV sync-token).
- **Retained item**: an item no source holds any more, kept instead of deleted and hidden from the sync seam and the live reads until it is purged (§11).

## 3. Store layout

A store is a directory containing exactly:

```
mystore/
  pimdir.db            the SQLite database (may be accompanied by -wal / -shm)
  objects/             the content-addressed blob directory (§5)
    ab/cd/abcd…         a body, at objects/<h[0:2]>/<h[2:4]>/<hash>
```

A directory is a pimdir store if and only if it contains a pimdir.db whose `store_meta.format` is `'pimdir'`. The database *is* the marker; there is no separate marker file.

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
- **`bindings`**: one source's binding of an item, keyed `(collection, link_id, source)`. Carries the item's `handle` on that source, the three-way-merge base (`base_flags`, `base_object`, `base_revision`), and the unresolved-conflict pair `conflicted` / `conflict_revision` (§10).
- **`queue`**: the action queue (§15). Carries the append `id`, `created_at`, the diagnostic `producer`, the target `collection`, the `action` kind, the versioned JSON `payload`, the GC-pinning `object_hash`, and the `attempts` / `error` parking state.

An item plus a base per source is the whole model: **single-source is the N=1 case**, one binding. The only thing N≥2 adds is `deleted`, a removal that must linger until every source has dropped it.

Flags are a JSON array rather than a child table: the set is small per item and `json_each` makes "all unread in a collection" an ordinary query. A consumer with heavy flag-query needs MAY build its own derived table, a private index out of scope here.

### 4.4 Queries

The named, parameterised statements servicing the operations (§14) live under queries/, one file per concern: [collections](./queries/collections.sql), [items](./queries/items.sql), [bindings](./queries/bindings.sql), [sources](./queries/sources.sql), [objects](./queries/objects.sql), [queue](./queries/queue.sql). They are the reference form, bound with the §13 encodings; an implementation SHOULD use them verbatim and MAY substitute an equivalent that preserves the same invariants (§7).

## 5. The blob store

Object bytes live under objects/, one file per hash, **sharded two levels by hash prefix** (`objects/<hash[0:2]>/<hash[2:4]>/<hash>`) to keep any one directory small. The hash is encoded in lowercase base32 (RFC 4648, no padding), so the path is valid on every target filesystem.

- **Write** is atomic: write a temporary period-prefixed file in the same shard directory, `fsync`, then `rename` into place, then **`fsync` the shard directory**. The name being the content hash, a file is never rewritten. The directory sync is not optional bookkeeping: syncing the file makes its bytes durable and says nothing about the name that reaches them, while the database commit *is* durable, so without it a power loss can leave a committed row pointing at a body that never arrived. That is the one asymmetry the write order of §14 exists to prevent, the reverse leaving at worst an orphan file.
- **Reference counting**: `objects.refcount` MUST equal the number of pointers at that hash, counting an item's `object_hash` and `conflict_object`, a binding's `base_object`, and a queue row's `object_hash` (§15). A body waiting in the queue is pinned exactly like a referenced one, and so is the body of a retained item (§11). Refcounts are maintained in the same transaction as the writes that change them.
- **Garbage collection**: an object whose refcount reaches zero MAY be deleted, its blob file removed after the row. The sweep tests `refcount <= 0` rather than `= 0`, so a count a double release drove negative is still collected instead of leaking for good with nothing reporting it, and it matches the partial index `objects_garbage` exactly: without that index both halves of the sweep scan the whole `objects` table, on every write transaction. A store MAY instead recompute refcounts from the pointer columns and sweep orphans: O(placements), and immune to bookkeeping drift.
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

## 7. Integrity

- A store is self-checking: `PRAGMA integrity_check` on the database, plus recomputing an object's hash and comparing it to its `objects.hash` and blob filename, detects corruption with no external manifest.
- The refcount invariant (§5) and the schema's foreign keys are the structural invariants; an implementation MAY verify and repair refcounts by recomputation.
- The order of trust is **blob bytes > database row**. A body whose recomputed hash disagrees with its row is authoritative, and the row is repaired from it.

## 8. Concurrency and ownership

The store has a **single-owner** rule: at most one process, on one host, owns pimdir.db at a time, and only the owner mutates collections, items, bindings, sources and objects (beyond the producer upsert below). Owners SHOULD take an advisory lock on the store directory, so a second owner waits or exits instead of racing.

Two lesser roles exist beside it, both local-host only:

- **Readers** open the database read-only and see consistent WAL snapshots; any number may run concurrently.
- **Producers** request mutations without owning the store. Their only permitted write is the §15 enqueue transaction; they MUST NOT touch any other table, and MUST NOT assume when the owner will apply the action.

On a **network filesystem** (NFS/SMB), SQLite's cross-host locking is unreliable, so a store on a share MUST be owned by exactly one process on one host, typically a front daemon clients talk to rather than opening the file themselves. Two owners MUST NOT run, and an implementation SHOULD enforce single-instance with a lease. Such an owner MUST NOT rely on WAL's shared-memory (`-shm`) file or on `mmap`, both of which assume a local filesystem: it MUST use rollback-journal mode or `PRAGMA locking_mode = EXCLUSIVE`.

Because writes are transactional, a reconciled flag set or a multi-item move commits atomically, and a reader never observes a torn change.

## 9. Identity and dedup

Four identifiers, kept distinct:

- **handle**: the backend's per-collection id (IMAP UID, DAV href). It changes if the backend reassigns it, so it is never the cross-collection key.
- **link id**: the item's stable cross-collection identity (`Message-ID`, vCard/iCal `UID`), the dedup and threading key. **Internal**: a consumer keys reads and edits by `seq`.
- **hash**: content state and blob key; changes when the content changes (mutable-content backends only, mail bodies being immutable).
- **seq**: the store-global **public id** (`items.seq`), a small integer a consumer shows in place of the long link id, the same in every collection the item is filed in (§9.1).

Deduplication keys on equal **hash**, so a message filed in two mailboxes, or a body another collection already fetched, is stored once and opening it costs no network. Merging keys on **link id**, conservatively: a missed dedup is harmless, a wrong merge hides data.

All four are store-wide, and stay so when one store holds several accounts (§9.2). An identity or a body occurring in more than one collection or account is a fact the store reports (`list_link_placements`, `list_object_placements`, §14.1) rather than a merge it performs.

### 9.1 The public id (`seq`)

`link_id` is the right internal key and the wrong thing to show a user. Each item therefore carries a `seq`, a small integer a consumer displays and accepts wherever it would otherwise take a link id. It is a property of the item, not of a placement:

- **One id per link id, store-global.** The same `link_id` keeps the same `seq` in every collection it is filed in, drawn from one store-wide counter (`store_meta.next_seq`), so a merged view shows the item once and ids never clash between collections. This holds across accounts too (§9.2): equal link ids share a `seq` wherever they sit, which reports their equality without asserting the placements are one thing.
- **Assigned once, monotonic, never reused.** The store assigns a `seq` the first time it inserts an item with that `link_id`, in any collection, and reuses it afterwards. The counter only increases, so a stale id never silently addresses a different item.
- **Resolved back to `link_id`.** A consumer reads and edits by `(collection, seq)`, which is unique, and the store maps it to the link id internally.

### 9.2 Accounts

One store MAY hold the collections of several accounts. `collections.account` carries an opaque, owner-chosen id (an address, a config name), `NULL` in a single-account store, which is the shape everything below degenerates to.

**What the column is.** A grouping key, not an addressing one. `collections.id` stays unique store-wide, so an owner filing two accounts in one store namespaces their collection ids (`work/INBOX`, `home/INBOX`) exactly as it would have without the column. Its job is to make the grouping an indexed `WHERE` rather than a prefix match a reader has to know the owner's naming convention to perform.

**What it scopes: nothing.** Link ids, hashes and `seq`s keep the meaning §9 gives them, store-wide, whatever account a collection belongs to. The same `link_id` in two accounts is two placements sharing one `seq`; the same body is one object with two placements, refcounted twice (§5). Bodies carry no account, so dedup never did.

**What multiplicity means is the interface's job.** The store's contract is to make it visible through `list_link_placements` and `list_object_placements` (§14.1). A mail view lists the placements, because two receipts of a newsletter have two read states; a contact view may offer to merge them, because one person in two address books is usually one person. Neither is baked in, so a kind this spec has not anticipated is not pre-judged. It is the same discipline as `kind` being declared rather than derived (§14) and `meta` staying opaque.

**What the account does not change.**

- **Ownership** (§8): one store still has one writing owner, so an owner wanting to sync accounts in parallel processes MUST give each account its own store.
- **Sources** (§10), keyed `(collection, source)` and therefore already inside one account.
- **Collision risk on `link_id`**: two unrelated servers may mint the same vCard `UID`, and those placements then share a `seq` while being different people. §9 already answers it: merging is conservative, and a consumer that cannot tolerate a false pairing compares bodies rather than identities.

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

The detail `level` lets an item be known before its body is fetched, so enumeration stays cheap and bodies hydrate lazily. `deleted` carries a removal across sources until every one has dropped it, and the item is then **retired rather than erased** (§11). A single-source store degenerates to one binding per item.

Two content divergences are recorded, and they are **not the same fact**:

- **Cross-source** (`items.conflicted`, `items.conflict_object`): two sources edited the shared body differently. It belongs to the item, being a statement about its sources disagreeing.
- **Source-versus-its-own-remote** (`bindings.conflicted`, `bindings.conflict_revision`): one source's own three-way merge diverged from its remote and was left unresolved. It belongs to that binding, since one source can be conflicted while another is in sync.

A store MUST persist both independently, and neither MUST set the other. A sync layer that cannot read its unresolved conflicts back re-derives on every run the push the remote already rejected and never converges, and a client cannot tell which items need a human. A binding's conflict MUST be cleared when the sync layer writes any resolved state for it, so resolving is an ordinary edit rather than a dedicated operation.

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
- **Purge is the only true delete.** A row leaves the store only through `purge_item` or `purge_retained_before`. The item row goes, its bindings cascade, and the body it released is unlinked by the ordinary refcount sweep (§5, §14), so purge needs no garbage collection of its own. A purge MUST NOT take a live item: both statements are guarded on `retained_at IS NOT NULL`.
- **A reappearing link id revives.** A link id that comes back while a retained row holds its primary key SHALL **revive** that row (`revive_item`: stamps cleared, `deleted` back to `0`) and adopt the new content, rather than conflict on the key. One branch serves both a source-side resurrection and a client `add` (§15.3). The revived row keeps its `seq` (§9.1) and whatever `object_hash`, `flags` and `meta` retention preserved, so a restore costs no network.
- **Retention is not durable state a source can observe.** `retained_by` is diagnostic and nothing keys on it. A retained item has no bindings, so it participates in no merge and pushes nothing; reviving it stages it as an ordinary local creation.

### 11.2 Purging

- **`purge_item(collection, seq)`**: one retained item by its public id, an operator emptying one thing out of the trash.
- **`purge_retained_before(cutoff)`**: every item retired before an RFC 3339 instant, store-wide, the scheduled sweep. The owner computes `cutoff` from its own retention duration and passes it in, so the store neither reads a clock nor holds the policy. Never sweeping reclaims nothing, and a cutoff of *now* reproduces the terminal-delete behaviour of a store that never retained, which is why no on/off switch is needed.

`retained_bytes()` (§14.1) reports what retention is holding, so an operator can see the cost of a policy before choosing a duration.

## 12. Collection generation

`collections.generation` is the collection's **handle-space epoch**: the owner MUST bump it, in the same transaction as the rebuild, whenever it discards and re-learns the collection's handles (an identity reset such as an IMAP UIDVALIDITY change). Readers exposing epoch-dependent protocol values derive them from it (an IMAP frontend maps `generation` to the UIDVALIDITY it advertises), so "the ids you cached are void" survives the process split without a side channel.

Ordinary syncs, full resyncs from an expired checkpoint, and content changes MUST NOT bump it.

## 13. Encodings

Two implementations produce byte-identical stores only if they encode the model into columns identically. These rules are normative.

- **`level`** (INTEGER): `0` probed, `1` meta, `2` full.
- **`deleted` / `conflicted`** (INTEGER): `0` or `1`.
- **`conflict`** (TEXT): the collection's cross-source content-conflict policy: `'manual'`, `'prefer-incoming'` or `'prefer-existing'`.
- **`flags` / `base_flags`** (TEXT): a JSON array of the raw flag strings, sorted ascending by code point so the encoding is canonical (e.g. `["$flagged","\\Seen"]`). `NULL` means *unknown* (not yet fetched), `'[]'` means *known-empty*; the two are distinct.
- **`object_hash` / `base_object` / `conflict_object`** (TEXT): a content hash under `store_meta.hash_algo`, base32, or `NULL`.
- **`link_id`** (TEXT): the cross-source identity an item is keyed by.
- **`meta`** (TEXT): an opaque application-defined summary blob, or `NULL` until a `Meta` fetch. The store never parses it.
- **`sort_key`** (TEXT): the item's position in its collection's natural order (§9.3), written beside `meta` and never derived by the store. `''` means *unknown*, and is the default. Ordering is the default `BINARY` collation, so a writer MUST encode the key so that byte order **is** the intended order: a timestamp as RFC 3339 in UTC at a fixed width (`2026-08-01T10:00:00Z`), never a local offset, since `+02:00` and `Z` sort apart while naming the same instant.

  It is also the one column exempt from the byte-identical rule above: a key derived from a zoned timestamp resolves through a time zone database, so two correct writers on different tzdb versions may write different keys. §9.3 is what makes that harmless: a key is a presentation fact, and a wrong one mis-sorts a list and loses nothing.
- **`base_revision`** (TEXT): an opaque etag/modseq for mutable-content backends, or `NULL`.
- **`conflicted`** (INTEGER, on a binding): whether *this source* and its own remote diverged and were left unresolved. Distinct from `items.conflicted` (§10).
- **`conflict_revision`** (TEXT): the remote revision observed when the binding was marked conflicted, or `NULL`. A binding that is not conflicted MUST NOT carry one, so a resolved binding cannot hand a stale revision to the next sync.
- **`retained_at`** (TEXT): the RFC 3339 instant the item's last source binding vanished, or `NULL` while it is live (§11). It is stamped by SQLite itself (`strftime('%Y-%m-%dT%H:%M:%fZ','now')`) in the retiring update, so every implementation writes the same shape and none plumbs a clock through to reach it. It records when the last binding *went*, not when a source deleted the item, which is unknowable; a revive clears it.
- **`retained_by`** (TEXT): the source whose removal retired the item, or `NULL`. Diagnostic only.
- **`checkpoint`** (BLOB): opaque sync-cursor bytes, or `NULL`.
- A binding's `base` is present iff at least one of `base_flags`, `base_object`, `base_revision` is non-`NULL`; absent, all three are `NULL`.
- **`action`** (TEXT): the action kind. The kinds this format defines are `'add'`, `'set-flags'`, `'remove'`, `'move'`, `'copy'` and `'update'` (§15.3); the column is open, and an owner that does not know a kind skips it rather than parking it (§15.2).
- **`payload`** (TEXT): versioned JSON, shape per action kind (§15), leading integer `v`.
- **`error`** (TEXT): `NULL` while an action is pending; non-`NULL` records the failure that parked it.
- **`generation`** (INTEGER): the collection's handle-space epoch, starting at 1 (§12).

## 14. Operations

The operations are serviced by the canonical statements under queries/ (§4.4), bound with the §13 encodings. The statements are the reference form; §7's invariants are what bind, and an implementation MAY use an equivalent.

A store is opened *as one source*. `load` projects the collection's shared items into the placements this source holds, and `write` folds this source's changes back.

- **`load(collection)`** reads the shared items and bindings (`load_items` + `load_bindings`, with `load_conflict`), projects them for this source, and reads its `load_checkpoint`. Freshly probed placements have no link id to key an item on, so an implementation holds them aside (in memory, or a residual table) until a `Meta` upgrade links them.
- **`lookup_objects(links)`** runs `lookup_objects` with `:links` bound to a JSON array of link-id strings.
- **`write(ops)`** runs as **one transaction**:
  1. A `StoreObject` carries the object's index row and, **optionally, its bytes**. Carrying bytes, the writer writes them to the blob file first (temporary file → `fsync` → `rename`, §5), then runs `store_object`. Carrying none, the body is already durable at its sharded path, streamed there by a consumer that fetched it without holding it whole, and whoever emits a byteless `StoreObject` MUST have completed that write first. Either form lands the object before the placement referencing it.

     A `SetCheckpoint` runs `ensure_collection` then `upsert_checkpoint` for this source.

     Placement upserts and drops are merged into the shared items and bindings, and the merged result is persisted, `set_conflict` carrying the collection's policy. The reference form is a load-all / replace-all per touched collection (`retain_item` for every item the result no longer holds, then `delete_items`, then `insert_item` / `insert_binding`). An implementation MAY instead persist the diff: §4.4 permits it because the persisted state is identical.

     An implementation persisting the diff SHOULD also **read** by the batch rather than by the collection: `load_items_by_link` and `load_bindings_by_link` bound to the link ids the batch names, resolving each dropped handle to its link id with `link_for_handle` first. The batch only ever produces writes for the items it names, so the rest of the collection is read and merged to conclude that nothing changed, and that read, not the writes, is what a small write actually costs: it grows with the mailbox instead of with the batch. Measured on the reference implementation, one flag on one message went from 3.5 ms at a thousand items and 59 ms at sixteen thousand, cleanly linear, to a flat 150 to 175 µs across the same range.

     An item the merge leaves with no binding at all is **retained, not deleted** (§11). Both forms agree on it: `delete_items` spares retained rows and `load_items` never returns one, so a retained item is outside the replace-all cycle and a reappearing link id revives its row rather than colliding with it.
  2. Bring the refcount of every object the batch touched back in line with the §5 invariant, in the same transaction. The reference form is `recompute_refcounts`, O(items+bindings+queue); an implementation MAY instead adjust each affected hash by the batch's net change (`adjust_refcount`, O(changes)).
  3. Run `list_garbage_objects`, remembering the hashes; run `delete_garbage_objects`.
  4. Commit.
  5. **After** the commit, unlink the blob files of the garbage hashes, so a crash leaves at worst an orphan file (harmless, swept by the next batch) rather than a row pointing at a missing body.

An implementation MAY skip the refcount and GC steps on a batch that stored or dropped no objects.

Three further operations belong to the §15 queue: **`enqueue(collection, action, payload)`**, **`drain(collection)`** and **`cancel(id)`** (§15.5). Retention adds **`purge(collection, seq)`** and **`purge_retained_before(cutoff)`** (§11.2), both owner writes.

A collection's `kind` is **declared, never derived**: which media type a collection holds is configuration, not something a sync layer can infer from what it pulls. Whoever configures the store declares it with **`set_collection_kind(collection, account, kind)`**, out of band from `write`, and any process reads it back with `load_kind`. The lazy path a write runs to guarantee its foreign-key target, `ensure_collection`, inserts an empty kind and MUST NOT overwrite a declared one, so either may run first. An empty `kind` means "created by a sync, never declared", which is distinct from a collection the store has never seen.

The `account` (§9.2) is configuration in the same sense, and both creation paths bind it without overwriting, so a collection cannot change accounts as a side effect of a sync declaring its media type. Re-accounting is the deliberate **`set_collection_account(collection, account)`**, and because the account partitions no identifier it disturbs nothing.

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
- **`list_link_placements(link_id)`** returns every live placement of one identity with its collection and account, and **`list_object_placements(hash)`** does the same by body, pairing placements two servers gave different link ids (§9.2).
- **`list_retained_page(collection, after, limit)`** returns a keyset page of **retained** items (§11), the live shape plus `retained_at`, `retained_by` and the body's `size`, under the same `:after` contract. **`count_retained(collection)`** counts them.
- **`retained_bytes()`** totals, store-wide, the size of the distinct bodies retained items hold: an upper bound on what a full purge would reclaim, since a body a live item also points at survives the sweep (§5).
- **`list_sources()`** returns the distinct source names the store has synced, so a producer can discover which source to attribute its writes to.
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

A producer enqueues in **one transaction**: `ensure_collection`, then, when the payload references a body, at most one `store_object` upsert (the blob file having been written durably first, §5), then one `enqueue_action` insert carrying that hash in `object_hash` so the pending body is pinned (§5). This is the only write a non-owner may perform (§8). How the producer nudges the owner to run is out of scope, and a producer MUST NOT rely on any application deadline.

### 15.2 Applying

The owner drains each collection's pending actions in ascending `id`. An action is applied to the items and bindings and its row deleted **in the same transaction**, so application is exactly-once and never partially visible; because applying is a pure store mutation, that transaction never spans network I/O.

The delete is `claim_action`, and it runs **first** in that transaction, not last. `load_pending_actions` is read outside any transaction, so a second owner may hold the same list: deleting at the end has both apply the row, and `add` and `copy` are not idempotent. Claiming it first makes exactly-once a property of the statement rather than a convention about who runs the drain, and it is what §8's advisory lock would otherwise be load-bearing for. A claim that deletes no row means another owner got there first, and there is nothing left to apply: the transaction ends without touching anything.

An action that fails is retried (`bump_attempts`, leaving the row pending). One the owner judges permanently unappliable is **parked**: `error` is set, the action skipped, later actions proceeding. Parked actions are left for operators, and the owner MUST NOT delete them silently.

**Skipping is not parking.** Kinds are extensible (§15.3), so one queue legitimately holds store mutations any owner can apply beside capability-bound intents only a particular process can perform (a mail submission needs a send channel this format knows nothing about). An owner that does not recognise a kind, **or recognises it but lacks the capability**, SHALL skip the row: it stays pending, untouched, `error` still `NULL`, and the owner MUST NOT park it, since parking asserts a permanence that is false about work another process will do. A skipped action MUST NOT block later actions and its `attempts` SHOULD NOT be bumped, a skip being no attempt. The row keeps its `id`, so the owner that can perform it still sees it in append order.

A drain therefore has three outcomes per row: applied, parked and skipped.

### 15.3 Actions

The format carries two things about an action: a **kind** and a **versioned JSON payload**, one shape per kind. Existing items are addressed by their public id `seq` (§9.1). At `v: 1`:

- **`add`**: `{ "v": 1, "link_id": …?, "flags": […], "object": hash?, "meta": {…}?, "handle": …? }`. Creates an item, staged as a local creation for the sync layer to push; `object` matches the row's `object_hash`. A duplicate `link_id` parks the action **unless the row holding it is retained**, in which case the action revives it (§11), so restoring needs no action kind of its own.
- **`set-flags`**: `{ "v": 1, "seq": n, "flags": […] }`. Replaces the flag set, absolute rather than a delta, so reapplication is idempotent.
- **`remove`**: `{ "v": 1, "seq": n }`. Removes the item from the collection; already-absent is success.
- **`move`**: `{ "v": 1, "seq": n, "to": collection }`. Refiles the item; `copy` is the same shape without the removal.
- **`update`**: `{ "v": 1, "seq": n, "object": hash, "meta": {…}? }`. Repoints a mutable-content item's body.

These six are the kinds the format *defines*, not the kinds it permits: `action` is an open string (§13) and `payload` is JSON the store never parses, so an application MAY carry a kind of its own, versioned the same way. A mail submission is the worked example, defined by the tool that can actually send. The store owes such a row exactly what it owes any other: append order, blob pinning, and the §15.2 skip rule.

### 15.4 Reading the queue

Readers MAY overlay a collection's pending actions on their projection (`load_pending_actions`) for read-your-writes, so a just-queued send shows as pending before the owner has applied it. Change is detected by polling `PRAGMA data_version`.

### 15.5 Cancelling and acknowledging

A pending or parked row MAY be removed **by request** (`cancel_action`): an operator withdrawing an action, or the process that carried out a capability-bound intent acknowledging it is done. Without it a queued action is unretractable, since only the apply path deletes a row.

- The delete SHALL run in one transaction with the refcount settle (§14), so the row's `object_hash` pin is released in the same commit and an unreferenced body falls to the ordinary sweep (§5).
- Cancelling is an owner write (§8), so a producer wanting to withdraw an action asks the process holding the owner role.
- Cancelling an already-applied action is impossible by construction: application deletes the row with its effects (§15.2), so an id is either queued or gone.
- Acknowledging is the same delete from the performer's side. An intent whose effect is not a store mutation is therefore **at-least-once**: a crash between the effect and the commit leaves the row pending and it is performed again. Deduplicating, where it matters, is the performer's job.

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
  "date": "2026-08-01T10:00:00Z",  // string, optional, RFC 3339
  "size": 1234                     // integer, optional, raw message octets
}
```

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

Unlike mail, a card has **one** derivation: a CardDAV `sync-collection` REPORT returns hrefs and ETags but no `UID`, so a card resolves at `Full` only. A card carries no flags either, so its `flags` is a known-empty `'[]'` rather than `NULL`.

Cards are **mutable**, which mail is not: the same card is edited in place under a changing ETag, so its `revision` (§13) moves while its `link_id` does not.

**`sort_key`**: the display name (`fn`), normalised for ordering rather than display: casefolded, leading and trailing whitespace removed. Read ascending. A card with no `FN` keeps `''` and sorts to the head, where a nameless contact is visible rather than buried. Normalising is what keeps the order stable across writers, which would otherwise interleave `alice` and `Alice` differently.

### A.3 `text/calendar` (`v: 1`)

**The item is the calendar object resource, not the component.** RFC 4791 §4.1 requires the components sharing a `UID` to live in the same resource, so a recurrence set stays whole, and requires that `UID` to be unique within its collection. A recurring series and its modified instances are therefore **one** item: one blob carrying the master, every `RECURRENCE-ID` override and the `VTIMEZONE`s they reference, under one `link_id`.

`(collection, link_id)` is then exactly the uniqueness CalDAV itself enforces, an override is a body edit rather than an item of its own, and the resource keeps the one href and ETag a binding records. A connector to an instance-granular source (a JSON calendar API handing each modified instance over separately) MUST reassemble the set into one resource before writing it, or two stores of the same calendar disagree about how many items it holds.

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
  "due": null,                        // string, optional, VTODO only
  "recurring": true,                  // bool, optional: carries an RRULE or an RDATE
  "until": "20261231T235959Z",        // string, optional, the RRULE's UNTIL verbatim
  "size": 421                         // integer, optional, raw item octets
}
```

The `link_id` is the `UID`, which identifies the same object across sources (RFC 5545 §3.8.4.7); content carrying no usable `UID` falls back to a writer-derived id rather than being refused. `component` names what a reader renders the resource as, and a resource may hold only one component type anyway (RFC 4791 §4.1, `VTIMEZONE` aside). `due` belongs to a `VTODO` alone and `dtend` to the components that have an end, both absent otherwise rather than merely unknown. The summary describes the master, the component carrying no `RECURRENCE-ID`.

Times are carried **verbatim**, with the `TZID` parameter and the `VALUE` type beside them, rather than as resolved instants. A reader holding a time zone database re-derives an instant in its own zone without fetching the body, and one holding none displays the wall time the calendar wrote instead of a UTC claim a writer fabricated. The single resolved projection is the `sort_key` below, so the store never carries two answers to the same question.

Like a card, a calendar object is **mutable**, so its `revision` moves while its `link_id` does not, and it carries no flags, so its `flags` is `'[]'`.

**`sort_key`**: the item's start, normalised to RFC 3339 in UTC at seconds precision (`2026-08-14T09:00:00Z`), read ascending for a chronological agenda. Which property that is depends on the component: `DTSTART` for a `VEVENT` or a `VJOURNAL`, and `DUE` then `DTSTART` for a `VTODO`, which is scheduled by its due date (RFC 5545 §3.8.2.3) and need not carry a `DTSTART` at all.

Only one of the shapes a start may take (RFC 5545 §3.3.4, §3.3.5) is an instant already, so the others normalise by convention:

- a **UTC** date-time is taken verbatim;
- a **zoned** date-time resolves through its `VTIMEZONE`, taking the earlier offset when the local time is ambiguous (the hour a fall-back repeats) and the offset after the transition when it does not exist (the hour a spring-forward skips), since a local time at a transition names two instants or none;
- a zoned date-time whose zone **will not resolve** (no `VTIMEZONE`, an unknown `TZID`) is read as floating rather than left unknown: the error is bounded by the offset, where dropping the key moves the item to the far end of the listing;
- a **date-only** value is read as `T00:00:00Z`;
- a **floating** date-time has its wall time read as UTC.

The last three are conventions rather than facts, the date-only case visibly so: an all-day item on the 11th sorts before an 08:00 item for a reader east of UTC and after it for one west, and the writer cannot know the reader's zone. An item with nothing parseable keeps `''` and lands at the head of an ascending listing.

A recurring item keys on its **first** occurrence, which is what `DTSTART` holds (RFC 5545 §3.8.2.4) and is fixed for the life of the series. A date-range read over recurring items therefore needs the recurrence expanded above the store, since expansion is a function of when you ask and no stored column answers it. That keeps the key deterministic and stable, and leaves time-dependence to the layer that has a clock.

`until` is what makes that expansion affordable. It carries the `UNTIL` of the `RRULE` verbatim, so `dtstart` and `until` bound the whole series and a reader can drop an item from a date range without materialising a single occurrence. Absent means the bound is unknown rather than absent: a rule bounded by `COUNT` states no `UNTIL`, and an unbounded one has none to state, so a reader that finds none expands to decide.
