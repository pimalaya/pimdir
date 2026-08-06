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
- **Item**: one message, event, task or contact.
- **Placement**: one item's presence in one collection: its handle, mutable state (flags), detail level, sync base, and a pointer to its object. The same logical item in two collections is two placements sharing one object.
- **Object**: a content-addressed, immutable item body. Index row in `objects`; bytes in a blob file.
- **Handle**: the backend's id for a placement within its collection (an IMAP UID, a JMAP id, a server file id).
- **Link id**: the item's cross-collection identity (`Message-ID`, vCard/iCal `UID`), the dedup and threading key. Never a byte size (it drifts on per-copy header rewrites).
- **Hash**: a cryptographic content hash of an object's bytes; its integrity value, dedup key and blob filename.
- **Checkpoint**: an opaque per-collection cursor recording the last point synced with the remote (QRESYNC state, JMAP state string, DAV sync-token).

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

The schema version is held in SQLite's built-in `PRAGMA user_version`, and mirrored in `store_meta.version`. Version 1, the current version, is defined by [migrations/0001_init.sql](./migrations/0001_init.sql): the whole schema, including the action queue and collection generations. The two MUST agree; an implementation opening a store where they disagree MUST treat it as corrupt.

### 4.3 Tables

The canonical schema is migrations/0001_init.sql; it is normative and this section is its prose companion.

- **`store_meta`** (one row): `format`, `version`, `hash_algo` (the hash used for every object: `blake3` RECOMMENDED, or `sha256-128`; recorded here so it is discoverable and swappable by a future migration), `created_at`.
- **`collections`**: `id`, `kind` (the media type shared by every item in it), `name`, `parent` (hierarchy by reference, never by row nesting), optional presentation (`color`, `description`, `sort_order`), the cross-source content-conflict `conflict` policy, and the handle-space `generation` (§15).
- **`sources`**: one row per source that syncs a collection (a server, a phone), keyed `(collection, source)`, carrying that source's opaque `checkpoint`. A single-source collection has one row.
- **`objects`**: `hash` (primary key, under `hash_algo`), `size`, and `refcount` (§5, §8). The bytes are *not* stored here.
- **`items`**: the shared truth of one logical item, keyed `(collection, link_id)`. Carries the mutable `flags` (a JSON array of strings), the current `object_hash`, the opaque `meta` summary, the detail `level` (0 probed → 1 meta → 2 full), and the cross-source state `deleted` / `conflicted` / `conflict_object`. It also carries `seq`, the item's store-global **public id** (§9.1): the `link_id` is the internal cross-source identity, but a client shows `seq` and resolves it back to `link_id`.
- **`bindings`**: one source's binding of an item, keyed `(collection, link_id, source)`. Carries the item's `handle` on that source and the three-way-merge base (`base_flags`, `base_object`, `base_revision`): the "light cache of the last agreed state". A single-source item has one binding; a two-server or server-plus-phone item has two.
- **`queue`**: the action queue (§14): mutations requested by processes that are not the store owner, applied by the owner in append order. Carries the append `id`, `created_at`, the diagnostic `producer`, the target `collection`, the `action` kind, the versioned JSON `payload`, the GC-pinning `object_hash`, and the `attempts` / `error` parking state.

An item and a base per source is the whole model: **single-source is the N=1 case** (one binding). The only thing N≥2 adds is `deleted`: a delete has to linger on the item until *every* source has dropped it, which N=1 never needs.

Flags are a JSON array of strings rather than a normalised child table: the set is small per item and SQLite's `json_each` makes "all unread in a collection" an ordinary query. A consumer with heavy flag-query needs MAY build its own derived flags table. That is a private index, out of scope here, exactly as any search index is. (This dissolves the file-per-item "reading a name is cheaper than a file" problem: a flag is a column, queried by index, never a `readdir`.)

### 4.4 Queries

The named, parameterised statements that service the store operations (§12) live under queries/, one file per concern: [collections](./queries/collections.sql), [items](./queries/items.sql), [bindings](./queries/bindings.sql), [sources](./queries/sources.sql), [objects](./queries/objects.sql) and [queue](./queries/queue.sql). They are the reference form, bound with the §11 encodings; an implementation SHOULD use them verbatim and MAY substitute an equivalent that preserves the same invariants (§8).

## 5. The blob store

Object bytes live as files under objects/, one file per hash, **sharded two levels by hash prefix** (`objects/<hash[0:2]>/<hash[2:4]>/<hash>`) to keep any one directory small. The hash is encoded in a single-case, filesystem-safe alphabet (lowercase base32, RFC 4648, no padding) so the blob path is valid on every target filesystem.

- **Write** is atomic: write to a temporary period-prefixed file in the same shard directory, `fsync`, then `rename` into place. Because the name is the content hash, a body is immutable and its file is never rewritten.
- **Reference counting**: `objects.refcount` MUST equal the number of pointers at that hash, counting an item's `object_hash` and `conflict_object`, a binding's `base_object`, and a queue row's `object_hash` (§14): a body waiting in the queue is pinned exactly like a referenced one. Refcounts are maintained in the same transaction as the writes that change them.
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

### 9.1 The public id (`seq`)

The `link_id` is the right *internal* key (stable, cross-source) but the wrong thing to show a user: it is a long `Message-ID`/`UID` string. Each item therefore carries a `seq`: a small integer a consumer displays and accepts wherever it would otherwise take a link id (read, flag, move, delete). It is a property of the **message**, not of a mailbox placement, consistent with dedup and a merged view:

- **One id per message, store-global.** A message filed in several mailboxes (the same `link_id`) keeps the **same** `seq` in every one of them, so a merged / cross-mailbox view shows it once under one id and ids never clash between mailboxes. The `seq` is drawn from a single store-wide counter (`store_meta.next_seq`), not a per-collection one.
- **Assigned once, monotonic, never reused.** The store assigns a message's `seq` the first time it inserts an item with that `link_id` (in any collection) and reuses it for every later placement of the same `link_id`. The counter only ever increases, so a `seq` is not reused even after the message is deleted everywhere. A stale id never silently addresses a different message.
- **Resolved back to `link_id`.** A consumer reads/edits by `(collection, seq)`; the store maps it to the `link_id` and operates on the link id internally. `(collection, seq)` is unique (one placement per message per collection).

## 10. Sync model

The store is shaped for offline-first synchronisation against one or more remote sources. A shared item holds the merged truth; a per-source binding records the base, the last state agreed with that source. A sync layer above the store derives what changed locally (the current item versus the binding's base) and what changed remotely, and reconciles the two. The detail `level` lets an item be known before its body is fetched, so enumeration stays cheap and bodies hydrate lazily. `deleted` carries a removal across sources until every one has dropped it; `conflicted` and `conflict_object` record an unresolved cross-source content divergence for the consumer to settle. A single-source store degenerates to one binding per item and never needs the cross-source memory.

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
- **`checkpoint`** (BLOB): opaque sync-cursor bytes, or `NULL`.
- A binding's `base` is present iff at least one of `base_flags`, `base_object`, `base_revision` is non-`NULL`; absent, all three are `NULL`.
- **`action`** (TEXT): one of `'add'`, `'set-flags'`, `'remove'`, `'move'`, `'copy'`, `'update'` (§14).
- **`payload`** (TEXT): versioned JSON, shape per action kind (§14), leading integer `v`.
- **`error`** (TEXT): `NULL` while an action is pending; non-`NULL` records the failure that parked it.
- **`generation`** (INTEGER): the collection's handle-space epoch, starting at 1 (§15).

## 12. Operations

The store operations are serviced by the canonical statements under queries/ (§4.4), bound with the §11 encodings. The statements are the reference form; §8's invariants are what bind, and an implementation MAY use an equivalent statement.

A store is opened *as one source*. `load` and `write` translate between a per-source placement view and the stored `items` and `bindings`: `load` projects the collection's shared items into the placements this source holds (or should copy), and `write` folds this source's changes back.

- **`load(collection)`** reads the collection's shared items and bindings (`load_items` + `load_bindings`, with `load_conflict`), projects them for this source into placements, and reads this source's `load_checkpoint`. (Unlinked, freshly probed placements have no link id to key an item on; an implementation holds them aside (in memory, or a residual table) until a `Meta` upgrade links them.)
- **`lookup_objects(links)`** runs `lookup_objects` with `:links` bound to a JSON array of the link-id strings.
- **`write(ops)`** runs as **one transaction**:
  1. A `StoreObject` first writes its bytes to the blob file (temporary file → `fsync` → `rename` into the sharded path, §5) then runs `store_object`; the writer emits it before the placement that references it, so the body is durable first. A `SetCheckpoint` runs `ensure_collection` then `upsert_checkpoint` for this source. Placement upserts and drops are merged into the collection's shared items and bindings for this source, which are then saved: `set_conflict`, `delete_items`, and a re-`insert_item` / `insert_binding` of the merged result: a load-all / replace-all per touched collection.
  2. Run `recompute_refcounts`.
  3. Run `list_garbage_objects`, remembering the hashes; run `delete_garbage_objects`.
  4. Commit.
  5. **After** the commit, unlink the blob files of the garbage hashes. Deleting the file after the row means a crash leaves at worst an orphan file (harmless, swept by the next batch) rather than a row pointing at a missing body. It is the same durability ordering as object creation.

An implementation MAY skip the refcount/GC steps on a batch that stored or dropped no objects.

Two further operations belong to the §14 queue: **`enqueue(collection, action, payload)`**, the producer's only write, and **`drain(collection)`**, the owner's application of pending actions.

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

Flags are **not** in `meta`; they are the item's `flags` (§11). It is written by the sync connector on both the enumerate/`Meta` and the streamed/`Full` paths, and read by any client projecting the collection. Other kinds (`text/vcard`, `text/calendar`) define their own `v: 1` convention the same way when they are first written.

## 14. Action queue

The single-owner rule (§7) leaves every other process unable to mutate, yet frontends legitimately originate mutations: a submission daemon queuing a send, a server frontend flipping a flag, a client filing an item. The `queue` table is their write door: a **producer** appends a requested action, the **owner** applies it. The queue is domain-generic: actions address collections and public ids, never protocol concepts, so the same six kinds serve mail, contacts and calendars.

### 14.1 Producing

A producer enqueues in **one transaction**: `ensure_collection`, then, when the payload references a body, at most one `store_object` upsert (the blob file having been written durably first, per §5, whose atomic write needs no coordination), then one `enqueue_action` insert carrying that hash in `object_hash` so the pending body is pinned by the refcount invariant (§5). This transaction is the only write a non-owner may perform (§7). How the producer then nudges the owner to run (spawning it, a signal, a socket) is out of scope; a producer MUST NOT rely on any application deadline.

### 14.2 Applying

The owner drains each collection's pending actions in ascending `id`. Each action is applied to the items and bindings and its row deleted **in the same transaction**, so application is exactly-once and never partially visible; because applying is a pure store mutation (any remote push happens later, from the dirty state the application leaves behind), the transaction never spans network I/O. An action that fails is retried (`attempts` incremented); an action the owner judges permanently unappliable is **parked**: `error` is set, the action is skipped, and later actions of the collection proceed. Parked actions are left for operators and status surfaces; the owner MUST NOT delete them silently.

### 14.3 Actions

Payloads are JSON with a leading integer `v`, one shape per action kind. Existing items are addressed by their public id `seq` (§9.1), the same identifier a reading client already holds. At `v: 1`:

- **`add`**: `{ "v": 1, "link_id": …?, "flags": […], "object": hash?, "meta": {…}?, "handle": …? }`. Creates an item in the collection, staged as a local creation for the sync layer to push. `object` matches the row's `object_hash`. A duplicate `link_id` in the collection parks the action (the item already exists).
- **`set-flags`**: `{ "v": 1, "seq": n, "flags": […] }`. Replaces the item's flag set (absolute, never a delta, so reapplication is idempotent).
- **`remove`**: `{ "v": 1, "seq": n }`. Removes the item from the collection; already-absent is success, not an error.
- **`move`**: `{ "v": 1, "seq": n, "to": collection }`. Refiles the item; `copy` is the same shape without the removal.
- **`update`**: `{ "v": 1, "seq": n, "object": hash, "meta": {…}? }`. Repoints a mutable-content item's body (a contact or event edit).

### 14.4 Reading the queue

Readers MAY overlay a collection's pending actions on their item projection (`load_pending_actions`) for read-your-writes: a just-queued send shows in the Outbox before the owner has applied it. Readers detect store changes cheaply by polling `PRAGMA data_version`, which changes whenever another connection commits.

## 15. Collection generation

`collections.generation` is the collection's **handle-space epoch**: the owner MUST bump it, in the same transaction as the rebuild, whenever it discards and re-learns the collection's handles (a backend identity reset such as an IMAP UIDVALIDITY change forcing a rekey). Readers that expose epoch-dependent protocol values derive them from it (an IMAP frontend maps `generation` to the UIDVALIDITY it advertises), so "the ids you cached are void" survives the process split without a side channel. Ordinary syncs, full resyncs from an expired checkpoint, and content changes MUST NOT bump it.
