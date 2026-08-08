# Pimdir store specification

Status: draft

The on-disk store for text-based personal-information items (mail, calendar events, contacts, notes, tasks…). A pimdir store is a **SQLite database** (the queryable index and mutable state) plus a **content-addressed blob directory** (the item bodies, each stored as an immutable blob): a hybrid that keeps the scale, indexing and cross-OS uniformity of SQLite while keeping large bodies out of the database. A body edit (a mutable-content item such as a CardDAV contact) writes a new blob and repoints the item; each blob is immutable, an item's current body is not.

The key words MUST, MUST NOT, SHOULD, SHOULD NOT and MAY are to be interpreted as in RFC 2119.

## 1. Goals and lineage

Pimdir is the generalisation of what most of PIM stores already do (Apple Mail, Thunderbird, notmuch, evolution-data-server): keep an **indexed binary store** for state and queries, and the **large immutable content** beside it. Its goals, in priority order:

- **Generic**: one store for any text-based item kind, keyed by media type, not one store per domain.
- **Scalable and indexed**: hundreds of thousands of items with real secondary indexes (by link id, by flag, by object), not per-item file opens.
- **Portable**: the SQLite file format is byte-identical and endian-independent across every OS and architecture, with a stability commitment through 2050; none of the case-sensitivity, forbidden-character, `MAX_PATH` or extended-attribute problems that file-per-item layouts hit.
- **Transactional**: a whole flag-set change or a multi-item move is one ACID commit, not a sequence of independent renames a reader can catch mid-flight.
- **Rebuildable, not sacred**: the database is a *derived* index over the authoritative blobs and the remote; corruption is survivable by re-sync (§6, §8). The one exception is un-pushed local mutation, which only the database holds.

Restricting to SQLite specifically (not "any SQL database") is deliberate: the portability property comes from *SQLite the file format*: a single file you can copy, not a server you must run. SQL is merely the access API; implementations are free to use any language with a SQLite binding.

## 2. Terminology

- **Store**: a directory holding one database file and one blob directory.
- **Database**: the SQLite file pimdir.db holding collections, items and their per-source bindings, objects (index rows) and checkpoints.
- **Collection**: a mailbox, address book or calendar; a row in `collections`.
- **Account**: the identity a collection belongs to (a mail account, a CardDAV login). An opaque owner-chosen id in `collections.account`, `NULL` when the store holds one account. It groups collections for reading and filtering; it partitions no identifier, and the store never interprets it (§9.2).
- **Item**: one message, event, task or contact.
- **Placement**: one item's presence in one collection: its handle, mutable state (flags), detail level, sync base, and a pointer to its object. The same logical item in two collections is two placements sharing one object.
- **Object**: a content-addressed, immutable item body. Index row in `objects`; bytes in a blob file.
- **Handle**: the backend's id for a placement within its collection (an IMAP UID, a JMAP id, a server file id).
- **Link id**: the item's cross-collection identity (`Message-ID`, vCard/iCal `UID`), the dedup and threading key. Never a byte size (it drifts on per-copy header rewrites).
- **Hash**: a cryptographic content hash of an object's bytes; its integrity value, dedup key and blob filename.
- **Checkpoint**: an opaque per-collection cursor recording the last point synced with the remote (QRESYNC state, JMAP state string, DAV sync-token).
- **Retained item**: an item no source holds any more, kept by the store instead of deleted, hidden from the sync seam and from the live reads until it is purged (§16).

## 3. Store layout

A store is a directory containing exactly:

```
mystore/
  pimdir.db            the SQLite database (may be accompanied by -wal / -shm)
  objects/             the content-addressed blob directory (§5)
    ab/cd/abcd…         a body, at objects/<h[0:2]>/<h[2:4]>/<hash>
```

A directory is a pimdir store if and only if it contains a pimdir.db whose `store_meta.format` is `'pimdir'`. There is no separate marker file: the database *is* the marker.

## 4. The database

### 4.1 Requirements

- The database MUST be a SQLite database, file name pimdir.db.
- Implementations MUST require **SQLite ≥ 3.37** (2021), for `STRICT` tables and `DROP COLUMN`. All tables MUST be `STRICT`, so column types are enforced rather than subject to SQLite's default dynamic affinity. This is what makes the schema safe across implementations.
- `PRAGMA foreign_keys = ON` MUST be set per connection.
- For a local store, `PRAGMA journal_mode = WAL` is RECOMMENDED. For a store on a network filesystem, see §7.

### 4.2 Schema version

The schema version is held in SQLite's built-in `PRAGMA user_version`, and mirrored in `store_meta.version`. Version 1, the current version, is defined by [migrations/0001_init.sql](./migrations/0001_init.sql): the whole schema, including the action queue, retention (§16) and collection generations. The two MUST agree; an implementation opening a store where they disagree MUST treat it as corrupt.

While this spec is `draft`, version 1 is **edited in place** (§6): a schema change folds into that one script and `user_version` stays `1`. Retention landed that way, so it is not a version 2 and there is no migration to it; a store stamped with any other version, or created by an earlier draft of version 1, is recreated, never migrated.

### 4.3 Tables

The canonical schema is migrations/0001_init.sql; it is normative and this section is its prose companion.

- **`store_meta`** (one row): `format`, `version`, `hash_algo` (the hash used for every object: `blake3` RECOMMENDED, or `sha256-128`; recorded here so it is discoverable and swappable by a future migration), `created_at`.
- **`collections`**: `id`, the owning `account` (§9.2, `NULL` in a single-account store), `kind` (the media type shared by every item in it), `name`, `parent` (hierarchy by reference, never by row nesting), optional presentation (`color`, `description`, `sort_order`), the cross-source content-conflict `conflict` policy, and the handle-space `generation` (§15).
- **`sources`**: one row per source that syncs a collection (a server, a phone), keyed `(collection, source)`, carrying that source's opaque `checkpoint`. A single-source collection has one row.
- **`objects`**: `hash` (primary key, under `hash_algo`), `size`, and `refcount` (§5, §8). The bytes are *not* stored here.
- **`items`**: the shared truth of one logical item, keyed `(collection, link_id)`. Carries the mutable `flags` (a JSON array of strings), the current `object_hash`, the opaque `meta` summary, the detail `level` (0 probed → 1 meta → 2 full), and the cross-source state `deleted` / `conflicted` / `conflict_object`. It also carries `seq`, the item's store-global **public id** (§9.1): the `link_id` is the internal cross-source identity, but a client shows `seq` and resolves it back to `link_id`. Finally it carries the retention stamps `retained_at` (the RFC 3339 instant the item's last source binding vanished, `NULL` while it is live) and `retained_by` (the source whose removal retired it, diagnostic only): a non-`NULL` `retained_at` is the persisted form of "no source holds this any more, and the store kept it anyway" (§16). The partial index `items_retained` scopes the trash listing and the purge sweep to those rows.
- **`bindings`**: one source's binding of an item, keyed `(collection, link_id, source)`. Carries the item's `handle` on that source, the three-way-merge base (`base_flags`, `base_object`, `base_revision`) — the "light cache of the last agreed state" — and the unresolved-conflict pair `conflicted` / `conflict_revision` (§10). A single-source item has one binding; a two-server or server-plus-phone item has two.
- **`queue`**: the action queue (§14): mutations requested by processes that are not the store owner, applied by the owner in append order. Carries the append `id`, `created_at`, the diagnostic `producer`, the target `collection`, the `action` kind, the versioned JSON `payload`, the GC-pinning `object_hash`, and the `attempts` / `error` parking state.

An item and a base per source is the whole model: **single-source is the N=1 case** (one binding). The only thing N≥2 adds is `deleted`: a delete has to linger on the item until *every* source has dropped it, which N=1 never needs.

Flags are a JSON array of strings rather than a normalised child table: the set is small per item and SQLite's `json_each` makes "all unread in a collection" an ordinary query. A consumer with heavy flag-query needs MAY build its own derived flags table. That is a private index, out of scope here, exactly as any search index is. (This dissolves the file-per-item "reading a name is cheaper than a file" problem: a flag is a column, queried by index, never a `readdir`.)

### 4.4 Queries

The named, parameterised statements that service the store operations (§12) live under queries/, one file per concern: [collections](./queries/collections.sql), [items](./queries/items.sql), [bindings](./queries/bindings.sql), [sources](./queries/sources.sql), [objects](./queries/objects.sql) and [queue](./queries/queue.sql). They are the reference form, bound with the §11 encodings; an implementation SHOULD use them verbatim and MAY substitute an equivalent that preserves the same invariants (§8).

## 5. The blob store

Object bytes live as files under objects/, one file per hash, **sharded two levels by hash prefix** (`objects/<hash[0:2]>/<hash[2:4]>/<hash>`) to keep any one directory small. The hash is encoded in a single-case, filesystem-safe alphabet (lowercase base32, RFC 4648, no padding) so the blob path is valid on every target filesystem.

- **Write** is atomic: write to a temporary period-prefixed file in the same shard directory, `fsync`, then `rename` into place. Because the name is the content hash, a body is immutable and its file is never rewritten.
- **Reference counting**: `objects.refcount` MUST equal the number of pointers at that hash, counting an item's `object_hash` and `conflict_object`, a binding's `base_object`, and a queue row's `object_hash` (§14): a body waiting in the queue is pinned exactly like a referenced one, and so is the body of a retained item, which keeps its `object_hash` until it is purged (§16). Refcounts are maintained in the same transaction as the writes that change them.
- **Garbage collection**: an object whose refcount reaches zero MAY be deleted; its blob file is removed after the row. A store MAY instead recompute refcounts from the placement columns and sweep orphans: O(placements), and immune to incremental-bookkeeping drift.
- Bodies are content-addressed, so an identical body delivered to two collections is stored once; copy, move and undelete are pointer edits, never byte copies.

Keeping bodies out of the database is what makes the database a *rebuildable cache*: an implementation MAY drop and rebuild pimdir.db from the blobs and a fresh remote sync (§6). The irreplaceable data survives any index corruption.

## 6. Migrations

Schema evolution is a set of ordered, forward-only SQL scripts under migrations/, named NNNN_description.sql (zero-padded, ascending). They are canonical: every implementation applies the identical SQL, in any language, behind a ~20-line runner.

The runner MUST:

1. Read `PRAGMA user_version` (0 for a fresh database).
2. For each migration whose number is greater than the current version, in ascending order: open a transaction, execute the script, set `PRAGMA user_version` to that number, commit. A failed script MUST roll back its transaction and stop.

Migrations are **forward-only**. There are no down-migrations because the database is derived: an implementation that meets a store newer than it understands, or a corrupt store, MAY rebuild from the blob store and a full re-sync instead of migrating down.

> **Caveat (normative):** the database is the *only* home of **un-pushed local mutation**: a flag change or delete made offline and not yet synced (an item whose current state has diverged from its per-source base). Rebuild-by-resync therefore MAY lose such changes. A migration MUST preserve item and binding state; rebuild is a last resort, not a substitute for migrating.

Because pre-3.35 SQLite could not drop or alter columns, migrations that reshape a table use the create-new / copy / drop-old / rename dance; on the required 3.37+ baseline `DROP COLUMN` is available directly.

> **While this spec is `draft` (normative):** version 1 is not yet frozen, so a schema change MAY be folded into [migrations/0001_init.sql](./migrations/0001_init.sql) in place rather than added as version 2. `PRAGMA user_version` stays `1`, and the ordered forward-only rule above governs every version from the first frozen one onwards. The retention columns (§16) are folded in exactly this way: they are part of version 1, not a migration to a version 2.
>
> The cost is that a store created by an earlier draft of version 1 is *not* detectably out of date: its `user_version` already matches, so the runner does nothing and the missing columns surface as query errors. An implementation servicing a draft store MUST therefore either reconcile the shape on open (adding a folded-in column with `ALTER TABLE … ADD COLUMN`, which is idempotent when guarded by `PRAGMA table_info`) or refuse the store with a clear message telling the operator to recreate it. Silently failing a query later is not acceptable. This whole allowance disappears when the spec leaves `draft`.

## 7. Concurrency and ownership

The store has a **single-owner** rule: at any time at most one process, on one host, owns pimdir.db. Only the owner mutates collections, items, bindings, sources and objects (beyond the producer upsert below). This is stronger than "serialize the requests" and is the invariant that makes the network case safe. Owners SHOULD take an advisory lock on the store directory so a second owner (an overlapping cron and a triggered run) waits or exits instead of racing.

Two lesser roles exist beside the owner, both local-host only:

- **Readers** open the database read-only and see consistent WAL snapshots; any number may run concurrently.
- **Producers** request mutations without owning the store: their only permitted write is the §14 enqueue transaction (an `ensure_collection`, at most one `store_object` upsert pinning a body they wrote to the blob directory, and one `queue` insert). Producers MUST NOT touch any other table, and MUST NOT assume when the owner will apply the action.

- **Local**: WAL mode gives concurrent readers plus one writer within a host; multiple local readers are fine.
- **Network filesystem (NFS/SMB)**: SQLite's cross-host advisory locking is unreliable there, so a store on a share MUST be owned by exactly one process on one host, typically a front daemon that clients talk to rather than opening the file themselves. Two owners (one per host) MUST NOT run; an implementation SHOULD enforce single-instance with a lease. Such an owner MUST NOT rely on WAL's shared-memory (`-shm`) file or on `mmap` (both assume a local filesystem): it MUST use either rollback-journal mode or `PRAGMA locking_mode = EXCLUSIVE` (which runs WAL without the shared-memory segment). With a single owner there is no cross-host locking to get wrong, so the network-filesystem hazards do not arise.

Because writes are transactional, a whole reconciled flag set or a multi-item move commits atomically; a reader never observes a torn multi-item change.

## 8. Integrity

- A store is self-checking: `PRAGMA integrity_check` on the database, plus recomputing an object's hash and comparing it to its `objects.hash` / blob filename, detects corruption with no external manifest.
- The refcount invariant (§5) and the schema's foreign keys are the structural invariants; an implementation MAY verify and repair refcounts by recomputation.
- The authoritative order of trust on conflict is: **blob bytes > database row**. A body whose recomputed hash disagrees with its row is authoritative, and the row is repaired from it.

## 9. Identity and dedup

Four identifiers, kept distinct:

- **handle**: the backend's per-collection id (IMAP UID, DAV href); changes if the backend reassigns it, so it is never the cross-collection key.
- **link id**: the item's stable cross-collection identity (`Message-ID`, vCard/iCal `UID`), the dedup and threading key. **Internal**: a store consumer keys reads and edits by the public **seq**, not the link id.
- **hash**: content state and the blob key; changes when the content changes (mutable-content backends only; mail bodies are immutable).
- **seq**: the item's store-global **public id** (`items.seq`): a small integer a consumer shows and accepts in place of the long link id, the same across every collection the message is filed in (§9.1).

Deduplication keys on equal **hash**, so a message filed in two mailboxes, or a body already fetched by another collection, is stored once. Opening it in a second collection costs no network. Merging keys on **link id**, conservatively: a missed dedup is harmless, a wrong merge hides data.

All four are store-wide, and stay so when one store holds several accounts (§9.2). An identity or a body occurring in more than one collection, or more than one account, is a fact the store reports rather than a merge it performs: §12.1's `list_link_placements` and `list_object_placements` return where, and the consumer decides what that means for its kind.

### 9.1 The public id (`seq`)

The `link_id` is the right *internal* key (stable, cross-source) but the wrong thing to show a user: it is a long `Message-ID`/`UID` string. Each item therefore carries a `seq`: a small integer a consumer displays and accepts wherever it would otherwise take a link id (read, flag, move, delete). It is a property of the **message**, not of a mailbox placement, consistent with dedup and a merged view:

- **One id per link id, store-global.** A message filed in several mailboxes (the same `link_id`) keeps the **same** `seq` in every one of them, so a merged / cross-mailbox view shows it once under one id and ids never clash between mailboxes. The `seq` is drawn from a single store-wide counter (`store_meta.next_seq`), not a per-collection one. This holds across accounts too (§9.2): the `seq` is the short form of the `link_id`, so equal link ids share it wherever they sit, which reports their equality without asserting that the placements are one thing.
- **Assigned once, monotonic, never reused.** The store assigns a message's `seq` the first time it inserts an item with that `link_id` (in any collection) and reuses it for every later placement of the same `link_id`. The counter only ever increases, so a `seq` is not reused even after the message is deleted everywhere. A stale id never silently addresses a different message.
- **Resolved back to `link_id`.** A consumer reads/edits by `(collection, seq)`; the store maps it to the `link_id` and operates on the link id internally. `(collection, seq)` is unique (one placement per message per collection).

### 9.2 Accounts

One store MAY hold the collections of several accounts. `collections.account` carries an opaque, owner-chosen account id (an address, a config name); it is `NULL` in a single-account store, which is the shape everything below degenerates to.

**What the column is.** A grouping and scoping key, not an addressing one. `collections.id` stays unique store-wide, so an owner filing two accounts in one store namespaces their collection ids (`work/INBOX`, `home/INBOX`) exactly as it would have without this column. The column's job is to make the grouping a query rather than a parse: "every collection of this account", the filter axis of a merged view, is an indexed `WHERE`, not a prefix match a reader has to know the owner's naming convention to perform.

**What it scopes: nothing.** The account partitions no identifier. Link ids, hashes and `seq`s all keep the meaning §9 gives them, store-wide, whatever account a collection belongs to. The store reports multiplicity and takes no position on it:

- The same `link_id` in two accounts' collections is **two placements sharing one `seq`**, because `seq` is the short form of the link id (§9.1) and the link id is genuinely equal. That is a restatement of what the content carries, not a claim that the two are one thing.
- The same body in two accounts is **one object, two placements**, refcounted twice (§5). Bodies carry no account, so dedup never did.

**Deciding what multiplicity means is the interface's job, not the store's.** The store's contract is to make it visible: `list_link_placements(link_id)` and `list_object_placements(hash)` (§12.1) return every collection and account an identity or a body occurs in. A mail view reads those and lists the placements, because two receipts of a newsletter have two read states and two servers. A contact view reads the same rows and may offer to merge them, because one person in two address books is usually one person. Neither behaviour is baked in, so both remain possible, and a kind the spec has not anticipated is not pre-judged.

This is the same discipline the rest of the store follows: `kind` is declared and never derived (§12), `conflict` is a policy the collection carries rather than one the engine assumes, and `meta` is opaque. A store that decided merges would be a store that had to be right about mail, contacts, calendars and whatever comes next.

**What the account does not change.**

- **Ownership** (§7). A store has one writing owner whatever it holds, so one store for several accounts means one owner process for all of them. An owner wanting to sync accounts in parallel processes MUST give each account its own store; that is the trade this column does not remove.
- **Sources** (§10), keyed `(collection, source)` and therefore already inside one account. Two accounts syncing against the same server are two accounts.
- **Collision risk on `link_id`.** Two unrelated servers may mint the same vCard `UID`, and those placements will then share a `seq` while being different people. This is a property of `link_id` itself, present long before accounts shared a store, and §9 already answers it: merging keys on link id **conservatively**, and a consumer that cannot tolerate a false pairing compares bodies (`list_object_placements`) rather than identities.

**Configuration lives outside.** The store records which account a collection belongs to and nothing else about it: no credentials, no endpoints, no display name, no enabled flag. Those belong to whatever configures the owner. A consequence worth stating: the store learns an account only through its collections, so an account with no collection yet does not appear in a listing, and one whose collections are all removed stops appearing. A consumer needing the full roster reads it from its own configuration and uses the store for content.

## 10. Sync model

The store is shaped for offline-first synchronisation against one or more remote sources. A shared item holds the merged truth; a per-source binding records the base, the last state agreed with that source. A sync layer above the store derives what changed locally (the current item versus the binding's base) and what changed remotely, and reconciles the two. The detail `level` lets an item be known before its body is fetched, so enumeration stays cheap and bodies hydrate lazily. `deleted` carries a removal across sources until every one has dropped it; when the last one has, the item is **retired rather than erased** (§16). A single-source store degenerates to one binding per item and never needs the cross-source memory.

Two content divergences are recorded, and they are **not the same fact**:

- **Cross-source** (`items.conflicted`, `items.conflict_object`): two sources edited the shared body differently. It belongs to the item, since it is a statement about the item's sources disagreeing with each other.
- **Source-versus-its-own-remote** (`bindings.conflicted`, `bindings.conflict_revision`): one source's own three-way merge diverged from its remote, and the sync layer left it unresolved. It belongs to that binding, since a two-source store can have one source conflicted with its server while the other is perfectly in sync.

A store MUST persist both independently; neither MUST set the other. A sync layer that cannot read its unresolved conflicts back gains no memory of them, so it re-derives on every run the push the remote already rejected and never converges, and a client reading the store cannot tell which items need a human. A binding's conflict MUST be cleared when the sync layer writes any resolved state for it, so resolving is an ordinary edit rather than a dedicated operation.

The store persists this model and services the operations in §12. Deriving pushes, merging and resolving conflicts belong to the sync layer above it, not to the store.

## 11. Encodings

Two implementations produce byte-identical stores only if they encode the model into columns identically. These rules are normative.

- **`level`** (INTEGER): `0` probed, `1` meta, `2` full.
- **`deleted` / `conflicted`** (INTEGER): `0` or `1`.
- **`conflict`** (TEXT): the collection's cross-source content-conflict policy: `'manual'`, `'prefer-incoming'` or `'prefer-existing'`.
- **`flags` / `base_flags`** (TEXT): a JSON array of the raw flag strings, sorted ascending by code point so the encoding is canonical (e.g. `["$flagged","\\Seen"]`). `NULL` means *unknown* (flags not yet fetched); `'[]'` means *known-empty*. The two are distinct.
- **`object_hash` / `base_object` / `conflict_object`** (TEXT): a content hash under `store_meta.hash_algo`, base32, or `NULL`.
- **`link_id`** (TEXT): the cross-source identity (an item is keyed by it).
- **`meta`** (TEXT): an opaque application-defined summary blob, or `NULL` until a `Meta` fetch. The store never parses it.
- **`base_revision`** (TEXT): an opaque etag/modseq for mutable-content backends, or `NULL`.
- **`conflicted`** (INTEGER, on a binding): `0` or `1` — whether *this source* and its own remote diverged and the sync layer left the placement unresolved. Distinct from `items.conflicted`, the cross-source divergence (§10).
- **`conflict_revision`** (TEXT): the remote revision observed when the binding was marked conflicted, or `NULL`. Non-`NULL` only while `conflicted` is `1`; a binding that is not conflicted MUST NOT carry one, so a resolved binding cannot hand a stale revision to the next sync.
- **`retained_at`** (TEXT): the RFC 3339 instant the item's last source binding vanished, or `NULL` while the item is live. Non-`NULL` is the retained state (§16). It is stamped by SQLite itself (`strftime('%Y-%m-%dT%H:%M:%fZ','now')`) in the retiring update, so every implementation writes the same shape and none plumbs a clock through to reach it. It records when the last binding *went*, not when a source deleted the item (unknowable); a revive clears it, so restoring an item and re-deleting it restarts the clock.
- **`retained_by`** (TEXT): the source whose removal retired the item, or `NULL`. Diagnostic only: no read, no sweep and no merge keys on it.
- **`checkpoint`** (BLOB): opaque sync-cursor bytes, or `NULL`.
- A binding's `base` is present iff at least one of `base_flags`, `base_object`, `base_revision` is non-`NULL`; absent, all three are `NULL`.
- **`action`** (TEXT): the action kind. The kinds this format defines are `'add'`, `'set-flags'`, `'remove'`, `'move'`, `'copy'` and `'update'` (§14.3); the column is open, so an application MAY carry a kind of its own, which an owner that does not know it skips rather than parks (§14.2).
- **`payload`** (TEXT): versioned JSON, shape per action kind (§14), leading integer `v`.
- **`error`** (TEXT): `NULL` while an action is pending; non-`NULL` records the failure that parked it.
- **`generation`** (INTEGER): the collection's handle-space epoch, starting at 1 (§15).

## 12. Operations

The store operations are serviced by the canonical statements under queries/ (§4.4), bound with the §11 encodings. The statements are the reference form; §8's invariants are what bind, and an implementation MAY use an equivalent statement.

A store is opened *as one source*. `load` and `write` translate between a per-source placement view and the stored `items` and `bindings`: `load` projects the collection's shared items into the placements this source holds (or should copy), and `write` folds this source's changes back.

- **`load(collection)`** reads the collection's shared items and bindings (`load_items` + `load_bindings`, with `load_conflict`), projects them for this source into placements, and reads this source's `load_checkpoint`. (Unlinked, freshly probed placements have no link id to key an item on; an implementation holds them aside (in memory, or a residual table) until a `Meta` upgrade links them.)
- **`lookup_objects(links)`** runs `lookup_objects` with `:links` bound to a JSON array of the link-id strings.
- **`write(ops)`** runs as **one transaction**:
  1. A `StoreObject` carries the object's index row and, **optionally, its bytes**. Carrying bytes, the writer writes them to the blob file first (temporary file → `fsync` → `rename` into the sharded path, §5), then runs `store_object`. Carrying none, the body is already durable at its sharded path, streamed straight into the blob store by a consumer that fetched it without holding it whole; the writer then runs `store_object` alone. Whoever emits a byteless `StoreObject` MUST have completed that blob write before emitting it. Either form lands the object before the placement that references it, so the body is durable first.

     A `SetCheckpoint` runs `ensure_collection` then `upsert_checkpoint` for this source.

     Placement upserts and drops are merged into the collection's shared items and bindings for this source, and the merged result is persisted, `set_conflict` carrying the collection's policy. The reference form is a load-all / replace-all per touched collection (`retain_item` for every item the merged result no longer holds, then `delete_items`, then `insert_item` / `insert_binding` of the merged result). An implementation MAY instead persist the diff, updating only the items and bindings that changed and retiring only what vanished: §4.4 permits the substitution because the persisted state is identical.

     An item the merge leaves with no binding at all is **retained, not deleted** (§16). The two forms agree on it: `delete_items` spares retained rows, `load_items` never returns one, so a retained item is simply outside the load-all / replace-all cycle, and a reappearing link id revives its row rather than colliding with it.
  2. Bring the refcount of every object the batch touched back in line with the §5 invariant, in this same transaction. The reference form is `recompute_refcounts`, a full recompute from the pointer tables, O(items+bindings+queue). An implementation MAY instead adjust each affected hash by the net change in pointers the batch made (`adjust_refcount`, O(changes)); §8's invariant is what binds, not the form, and a store MAY recompute at any time to repair drift.
  3. Run `list_garbage_objects`, remembering the hashes; run `delete_garbage_objects`.
  4. Commit.
  5. **After** the commit, unlink the blob files of the garbage hashes. Deleting the file after the row means a crash leaves at worst an orphan file (harmless, swept by the next batch) rather than a row pointing at a missing body. It is the same durability ordering as object creation.

An implementation MAY skip the refcount/GC steps on a batch that stored or dropped no objects.

Three further operations belong to the §14 queue: **`enqueue(collection, action, payload)`**, the producer's only write, **`drain(collection)`**, the owner's application of pending actions, and **`cancel(id)`**, the withdrawal of a queued or parked one (§14.5). Retention adds two more, both owner writes: **`purge(collection, seq)`** and **`purge_retained_before(cutoff)`** (§16.2).

A collection's `kind` (§4.3) is **declared, never derived**: which media type a collection holds is configuration (this store's mailboxes, that store's address books), not something a sync layer can infer from the items it pulls. Whoever configures the store declares it with **`set_collection_kind(collection, account, kind)`**, out of band from `write`, and any process reads it back with `load_kind`. The two creation paths coexist safely: `ensure_collection`, the lazy one a write runs to guarantee its foreign-key target, inserts an empty kind and MUST NOT overwrite a declared one, so either may run first. An empty `kind` therefore means "created lazily by a sync, never declared", which is distinct from a collection the store has never seen at all.

The collection's `account` (§9.2) is configuration in exactly the same sense, and both creation paths therefore bind it. Neither overwrites it: `ensure_collection` inserts or does nothing, and `set_collection_kind` updates the `kind` alone, so a collection cannot change accounts as a side effect of a sync declaring its media type. Re-accounting a collection is the deliberate **`set_collection_account(collection, account)`**. Because the account partitions no identifier (§9.2), moving a collection regroups it and disturbs nothing: `seq`s, link ids and objects are unaffected.

### 12.1 Reading the store

The operations above serve the store's **owner**. A **reader** (§7) opens the database read-only and projects it as a local backend: listing collections, paging items, resolving one of them. These reads are kind-agnostic, the same statements serving mail, contacts and calendars, and they are keyed by the public `seq` (§9.1), never by the internal `link_id`. Each one below is named after the reference statement that services it (§4.4), with its parameters.

- **`list_collections()`** returns every collection with its owning `account` (§9.2), display metadata and `generation` (§15), ordered by `sort_order` then `id`.
- **`list_collections_by_account(account)`** returns one account's collections, the same shape, and is the filter axis of a merged view; binding `NULL` selects the collections of a single-account store.
- **`list_accounts()`** returns the accounts owning at least one collection. A store knows an account only through its collections (§9.2), so this is not a configured roster and a consumer holding one reads it from its own configuration instead.
- **`list_items_page(collection, after, limit)`** returns a keyset page of the collection's live items; `:after` is the exclusive lower bound on `link_id`, the empty string starting from the beginning. Keyset rather than `OFFSET`, so paging costs the same at any depth and does not shift under a concurrent write.
- **`get_item(collection, seq)`** returns one live item.
- **`count_items(collection)`** counts the collection's live items.
- **`seq_by_link(collection, link_id)`** resolves the public id of an item whose link id the caller already holds, typically one it just staged through the queue.
- **`list_link_placements(link_id)`** returns every live placement of one identity, each with its collection and account. The multiplicity read (§9.2): the store reports where a link id occurs and takes no position on whether the placements are one thing, so a mail view can list them and a contact view can offer to merge them off the same rows.
- **`list_object_placements(hash)`** does the same on the dedup axis, by body rather than identity, so it pairs placements two servers gave different link ids.
- **`list_retained_page(collection, after, limit)`** returns a keyset page of the collection's **retained** items (§16), the same shape as the live page plus `retained_at`, `retained_by` and the body's `size`. Same `:after` contract. It is the only read that returns them: a trash view, never merged into the live listing.
- **`count_retained(collection)`** counts them, the counterpart of `count_items`.
- **`retained_bytes()`** totals, store-wide, the size of the distinct bodies retained items hold. It is an upper bound on what a full purge would reclaim: a body a live item also points at keeps a reference and survives the sweep (§5).
- **`list_sources()`** returns the distinct source names the store has synced, so a producer can discover which source to attribute its writes to.
- **`load_kind(collection)`** returns the collection's declared media type, empty when a sync created the row without one.

Three rules bind every read:

- **Live only.** A tombstone (`deleted = 1`) is the sync layer's memory of a removal, not an item; the live statements above exclude them, and a reader MUST NOT present one as a live item. A retained item (§16) is a tombstone by that same rule, so the same filter already hides it; the three retained reads are the deliberate exception, and a reader that surfaces their rows MUST present them as retained rather than as ordinary items.
- **Level-aware.** An item is projectable before its body exists: `level` (§11) says whether it is merely probed, summarised by `meta`, or full. A reader renders a list from `meta` and MUST treat an absent body as not yet hydrated rather than as an error or as a missing item; hydrating it is the owner's job, since a reader never writes (§7).
- **Snapshot-consistent.** A reader sees a consistent WAL snapshot, and any number of readers may run concurrently with the owner (§7).

A reader detects change cheaply by polling `PRAGMA data_version`, which moves whenever another connection commits, and MAY overlay the collection's pending actions on its projection for read-your-writes (§14.4).

## 13. Application meta conventions (informative)

The store never parses `meta` (§11): it is an opaque, application-defined summary blob. But the *writer* of a collection (a sync connector) and its *readers* (a client rendering a list) must agree on its shape per `kind`, so a reader can display an item without fetching its body. These conventions are **informative**, not enforced by the store, and each is JSON with a leading integer `v` for versioning. Absent optional fields mean "unknown".

### `message/rfc822` (`v: 1`)

```json
{
  "v": 1,
  "message_id": "abc@host",        // string, optional, bare Message-ID (no <>)
  "subject": "Hello",              // string, required (may be empty)
  "from": "alice@example.org",     // string, optional, first sender address
  "to": "bob@example.org",         // string, optional, first recipient address
  "date": "2026-08-01T10:00:00Z",  // string, optional, RFC 3339
  "size": 1234                     // integer, optional, raw message octets
}
```

Flags are **not** in `meta`; they are the item's `flags` (§11). It is written by the sync connector on both the enumerate/`Meta` and the streamed/`Full` paths, and read by any client projecting the collection.

### `text/vcard` (`v: 1`)

```json
{
  "v": 1,
  "uid": "urn:uuid:4fbe8971-0bc3",  // string, optional, the vCard UID verbatim
  "fn": "Jane Doe",                 // string, required (may be empty), display name
  "emails": ["jane@example.org"],   // array of strings, optional, every EMAIL
  "size": 421                       // integer, optional, raw card octets
}
```

Unlike mail, a card has **one** derivation: a CardDAV `sync-collection` REPORT returns hrefs and ETags but no `UID`, so a card resolves at `Full` only and there is no cheap summary tier to keep in agreement with it. A card also carries no flags, so its `flags` is a known-empty `'[]'` rather than `NULL`.

Cards are **mutable**, which mail is not: the same card is edited in place under a changing ETag, so its `revision` (§11) moves while its `link_id` does not.

The other kinds (`text/calendar`) define their own `v: 1` convention the same way when they are first written.

## 14. Action queue

The single-owner rule (§7) leaves every other process unable to mutate, yet frontends legitimately originate mutations: a submission daemon queuing a send, a server frontend flipping a flag, a client filing an item. The `queue` table is their write door: a **producer** appends a requested action, the **owner** applies it. The queue is domain-generic: actions address collections and public ids, never protocol concepts, so the six kinds this format defines serve mail, contacts and calendars alike. The kind is an open string beside a versioned payload (§14.3), so one queue also carries the intents an application defines for itself, which the owners that cannot perform them simply pass over (§14.2).

### 14.1 Producing

A producer enqueues in **one transaction**: `ensure_collection`, then, when the payload references a body, at most one `store_object` upsert (the blob file having been written durably first, per §5, whose atomic write needs no coordination), then one `enqueue_action` insert carrying that hash in `object_hash` so the pending body is pinned by the refcount invariant (§5). This transaction is the only write a non-owner may perform (§7). How the producer then nudges the owner to run (spawning it, a signal, a socket) is out of scope; a producer MUST NOT rely on any application deadline.

### 14.2 Applying

The owner drains each collection's pending actions in ascending `id`. Each action is applied to the items and bindings and its row deleted **in the same transaction**, so application is exactly-once and never partially visible; because applying is a pure store mutation (any remote push happens later, from the dirty state the application leaves behind), the transaction never spans network I/O. An action that fails is retried (`bump_attempts`, leaving the row pending so the next drain picks it up); an action the owner judges permanently unappliable is **parked**: `error` is set, the action is skipped, and later actions of the collection proceed. Parked actions are left for operators and status surfaces; the owner MUST NOT delete them silently.

**Skipping is not parking.** Not every action can be applied by every owner: kinds are extensible (§14.3), and one queue legitimately holds store mutations any owner can apply beside capability-bound intents only a particular process can perform (a mail submission needs a send channel and credentials this format knows nothing about). An owner that does not recognise an action's kind, **or recognises it but lacks the capability to perform it**, SHALL skip the row: it stays pending, untouched, with `error` still `NULL`, and the owner MUST NOT park it. Parking asserts that an action is permanently unappliable, which is false about work another process will do; a parked intent would be a lost one. A skipped action MUST NOT block the collection's later actions, and its `attempts` SHOULD NOT be bumped, a skip being no attempt. Because the row keeps its `id`, the owner that *can* perform it still sees it in append order relative to the rest.

A drain therefore has three outcomes per row, not two: applied (the row is deleted with its effects), parked (`error` set, permanently unappliable) and skipped (not this owner's to apply).

### 14.3 Actions

The format carries exactly two things about an action: a **kind** and a **versioned JSON payload**. Payloads are JSON with a leading integer `v`, one shape per kind. Existing items are addressed by their public id `seq` (§9.1), the same identifier a reading client already holds. At `v: 1`:

- **`add`**: `{ "v": 1, "link_id": …?, "flags": […], "object": hash?, "meta": {…}?, "handle": …? }`. Creates an item in the collection, staged as a local creation for the sync layer to push. `object` matches the row's `object_hash`. A duplicate `link_id` in the collection parks the action (the item already exists) **unless the row holding it is retained**, in which case the action revives it (§16): restoring a retained item is an ordinary `add`, over values the store still holds, and needs no action kind of its own.
- **`set-flags`**: `{ "v": 1, "seq": n, "flags": […] }`. Replaces the item's flag set (absolute, never a delta, so reapplication is idempotent).
- **`remove`**: `{ "v": 1, "seq": n }`. Removes the item from the collection; already-absent is success, not an error.
- **`move`**: `{ "v": 1, "seq": n, "to": collection }`. Refiles the item; `copy` is the same shape without the removal.
- **`update`**: `{ "v": 1, "seq": n, "object": hash, "meta": {…}? }`. Repoints a mutable-content item's body (a contact or event edit).

These six are the kinds the format *defines*, not the kinds it permits. `action` is an open string (§11) and `payload` is JSON the store never parses, so an application MAY carry a kind of its own, versioned the same way. A mail submission is the worked example: the envelope is its payload, the body is pinned by the row's `object_hash` like any other, and the kind is defined by the sync tool that can actually send, not by this format, which has no notion of a send channel. The store owes such a row exactly what it owes any other: append order, blob pinning, and the §14.2 rule that an owner unable to apply it skips it rather than parking it.

### 14.4 Reading the queue

Readers MAY overlay a collection's pending actions on their item projection (`load_pending_actions`) for read-your-writes: a just-queued send shows as pending before the owner has applied it. Readers detect store changes cheaply by polling `PRAGMA data_version`, which changes whenever another connection commits.

### 14.5 Cancelling and acknowledging

Application is not the only way out of the queue. A pending or parked row MAY be removed **by request** (`cancel_action`): an operator or frontend withdrawing an action it queued, or the process that carried out a capability-bound intent acknowledging that it is done. Without it a queued action is unretractable, since only the owner's apply path ever deletes a row.

- The delete SHALL run in one transaction with the refcount settle (§12), so the row's `object_hash` **pin is released in the same commit** that removes it: a body nothing else references falls to the ordinary sweep and its blob is unlinked after the commit, exactly as for any other dropped reference (§5).
- Cancelling is an owner write (§7). A producer's only permitted write remains the enqueue transaction, so a producer that wants to withdraw an action asks whichever process holds the owner role rather than deleting the row itself.
- Cancelling an already-applied action is impossible by construction: application deletes the row in the same transaction as its effects (§14.2), so an id is either still queued or already gone, never both.
- Acknowledging is the same delete seen from the performer's side. An intent whose effect is not a store mutation has nothing for the owner to apply, so its row goes once the effect is done. Such an intent is therefore **at-least-once**: a crash between the effect and the commit that removes the row leaves it pending and it is performed again. Deduplicating, where it matters, is the performer's job (a provider-side identity, or a marker written before the effect), not the format's.

## 15. Collection generation

`collections.generation` is the collection's **handle-space epoch**: the owner MUST bump it, in the same transaction as the rebuild, whenever it discards and re-learns the collection's handles (a backend identity reset such as an IMAP UIDVALIDITY change forcing a rekey). Readers that expose epoch-dependent protocol values derive them from it (an IMAP frontend maps `generation` to the UIDVALIDITY it advertises), so "the ids you cached are void" survives the process split without a side channel. Ordinary syncs, full resyncs from an expired checkpoint, and content changes MUST NOT bump it.

## 16. Retention

An item's removal from every source is not the same fact as its removal from the store. A pimdir store **retains**: when an item's last source binding vanishes, the row is stamped and kept rather than deleted, and only an explicit purge takes it away. A remote expunge therefore never destroys the local copy, which is what makes a store usable as a backup of a source it does not control.

Retention is the terminal state of the `deleted` memory, not a second mechanism beside it. `deleted` is the *in-flight* cross-source removal (dropped here, still held by another source, so the removal has yet to propagate); a **retained** item is one where that propagation has finished and nothing holds it any more. A retained row therefore carries `deleted = 1` and holds **no bindings** at all, and `retained_at` is the persisted, queryable form of exactly that.

Retention is **unconditional**. There is no switch, no per-store flag and no per-collection policy: whether a removal is terminal must read identically to every process that opens the store, so it is not configurable at all. *How long* to keep retained items, and *when* to sweep them, is the owner's schedule (a purge-after duration in its own configuration), not the store's semantics. Policy that changes what the data means lives here; policy that only schedules work lives above.

### 16.1 Requirements

- **Retire, do not delete.** When an item's last source binding vanishes, the store SHALL retain the row rather than delete it, setting `retained_at` to the instant the binding went and `retained_by` to the source whose removal retired it. The row SHALL keep its `object_hash`, so the body keeps its reference under the §5 refcount invariant and its blob survives garbage collection. The reference statement is `retain_item`; it stands exactly where a hard-deleting store would have issued the delete.
- **Stamped by SQLite.** `retained_at` SHALL be written by the retiring statement itself, `strftime('%Y-%m-%dT%H:%M:%fZ','now')`, so no implementation plumbs a clock through to reach it and two implementations stamp the same shape. The *cutoff* of a time-based purge is by contrast the caller's parameter (§16.2), which is what keeps a purge deterministic and testable despite the stamp being the store's.
- **Hidden from the sync seam.** A retained row SHALL be absent from the load that feeds the merge: `load_items` filters `retained_at IS NULL`. This is what makes retention safe rather than a source of resurrection loops, and it is a contract the sync engine above the store publishes: io-replica's storage spec (`io-replica/cairn/spec/storage.md`) states in *DropPlacement is the retention decision point* that every removal reaches storage as a drop the storage MAY retain instead of applying, and in *Hiding rows from load is safe* that the merge reconciles only the placements a `load` returns, so a hidden row is never re-derived, on a delta sync or on a full one. A store that retained rows *and* still returned them from `load` would re-upload every one of them on the next run; hiding them is not an optimisation but the condition of correctness. The same filter is why `delete_items` spares retained rows: they are outside the load-all / replace-all cycle entirely (§12).
- **Hidden from the read surface by default.** A retained item SHALL NOT appear in the live client reads. No new rule is needed for this: a retained row carries `deleted = 1` and the live-only rule of §12.1 already excludes it. `list_retained_page` and `count_retained` are the deliberate exception, a trash view a reader MUST present as retained rather than merged into the live listing.
- **Purge is the only true delete.** A row leaves the store only through a purge: by public id (`purge_item`) or by cutoff (`purge_retained_before`). Purging deletes the item row, its bindings cascade, and the body it released is unlinked by the ordinary refcount sweep (§5, §12): the reference drops, the object reaches refcount zero unless something else pins it, and its blob file is removed after the commit. Purge needs no garbage collection of its own. A purge MUST NOT take a live item: both statements are guarded on `retained_at IS NOT NULL`.
- **A reappearing link id revives.** A link id that comes back while a retained row holds its primary key `(collection, link_id)` SHALL **revive** that row (`revive_item`: `retained_at` and `retained_by` cleared, `deleted` back to `0`) and adopt the new content, rather than conflict on the key. One branch serves both cases: a source-side resurrection, and a client `add` restoring the item (§14.3). The revived row keeps its `seq`, so a restored item keeps the public id it always had (§9.1), and it keeps whatever `object_hash`, `flags` and `meta` retention preserved, so a restore costs no network.
- **Retention is not durable state a source can observe.** `retained_by` is diagnostic; nothing keys on it. A retained item has no bindings, so it participates in no merge and pushes nothing to any source. Reviving it stages it as a local creation like any other, which is precisely why restore needs no dedicated action kind.

### 16.2 Purging

Two purge shapes serve the two reasons to reclaim:

- **`purge_item(collection, seq)`**, one retained item by its public id: an operator emptying one thing out of the trash.
- **`purge_retained_before(cutoff)`**, every item retired before an RFC 3339 instant, store-wide: the scheduled sweep. The owner computes `cutoff` from its own retention duration and passes it in; the store neither reads a clock for it nor holds the policy. Unset (no sweep ever run) means nothing is ever reclaimed, and a cutoff of *now* reproduces the terminal-delete behaviour of a store that never retained, which is why no on/off switch is needed.

`retained_bytes()` (§12.1) reports what retention is holding, so an operator can see the cost of a policy before choosing a duration.
