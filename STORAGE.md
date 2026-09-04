# Pimdir storage specification

Status: draft

The storage part of the pimdir standard, and its base: a **SQLite database** (the index and the mutable state) plus a **content-addressed blob directory** (the bodies). The two layers over it are [SYNC.md](./SYNC.md), how sources reconcile through the store, and [SEARCH.md](./SEARCH.md), the index and query language over it.

This part binds every implementation, by the profile it meets: a **reader** opens the store and lists it, a **producer** also appends actions, an **owner** mutates it; [GUIDE.md](./GUIDE.md) §1 lists what each owes and an implementation MUST state which it is. The two layers presuppose the store: an implementation MAY omit either and MUST conform to those it offers.

A blob is immutable. A body edit writes a new blob and repoints the item.

[OVERVIEW.md](./OVERVIEW.md) explains the model this part fixes; [GUIDE.md](./GUIDE.md) runs its rules as procedures. Both are informative and this part wins on any disagreement.

The key words MUST, MUST NOT, SHOULD, SHOULD NOT and MAY are to be interpreted as in RFC 2119.

## Contents

1. [Goals](#1-goals)
2. [Terminology](#2-terminology)
3. [Store layout](#3-store-layout)
4. [The database](#4-the-database): [requirements](#41-requirements), [schema version](#42-schema-version), [tables](#43-tables), [queries](#44-queries), [the change feed](#45-the-change-feed)
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

[Annex A](#annex-a-summaries-normative) fixes the per-kind summary, address and `sort_key` derivations. It is normative.

## 1. Goals

Pimdir is what most PIM stores already are (Apple Mail, Thunderbird, notmuch, evolution-data-server): an indexed binary store for state, the large immutable content beside it. In priority order:

- **Generic**: one store for every kind the standard names, keyed by media type.
- **Scalable and indexed**: hundreds of thousands of items with real secondary indexes, never a file open per item.
- **Portable**: the SQLite file format is byte-identical across every OS and architecture, with none of the case, character and path-length pitfalls of file-per-item layouts.
- **Transactional**: a flag change or a multi-item move is one ACID commit.
- **Rebuildable**: the database is a derived index over the blobs and the remote, so corruption is survivable by re-sync (§6, §7). Un-pushed local mutation is the one thing only the database holds.

SQLite specifically: the portability is the file format, a file you copy rather than a server you run. Any language with a SQLite binding can implement this.

## 2. Terminology

- **Store**: a directory holding one database and one blob directory.
- **Database**: pimdir.db, holding collections, items, summaries, addresses, bindings, probes, objects and checkpoints.
- **Collection**: a mailbox, address book or calendar; a row in `collections`.
- **Account**: the identity a collection belongs to, an opaque owner-chosen id in `collections.account`, `NULL` in a single-account store (§9.2).
- **Item**: one message, contact, event, task or journal.
- **Placement**: one item's presence in one collection: handle, flags, level, base and a pointer to its object. One item in two collections is two placements sharing one object.
- **Summary**: what a reader lists an item from without its body, one row in its kind's table (Annex A), derived by the writer, never by the store.
- **Address**: one person an item names in one role, a row of one generic table across every kind (Annex A.6).
- **Probe**: a handle a source enumerated whose identity is not read yet, a row until the fetch that names it (SYNC.md §3).
- **Stamp**: the value of the store-wide change counter a row took when it last moved (§4.5).
- **Object**: a content-addressed, immutable body: a row in `objects`, bytes in a blob file.
- **Handle**: the backend's id for a placement in its collection (an IMAP UID, a DAV resource name).
- **Link id**: the item's key in its collection, assigned from the identity hint the content states (`Message-ID`, `UID`) and equal to it unless the collection already holds it (§9).
- **Hash**: the content hash of an object's bytes: its integrity value, dedup key and blob name.
- **Checkpoint**: an opaque per-source cursor (QRESYNC state, JMAP state, DAV sync-token).
- **Retained item**: an item no source holds any more, kept and hidden until purged (§11).
- **Owner lock**: the exclusive advisory lock on owner.lock the owning process holds (§8).
- **Staging lock**: the advisory lock on objects.lock producers hold shared while a body is written but not yet referenced, and the collector takes exclusively (§5, §8).

## 3. Store layout

```
mystore/
  pimdir.db            the SQLite database (may be accompanied by -wal / -shm)
  owner.lock           the owner lock, held exclusively (§8)
  objects.lock         the staging lock, held shared by producers (§8)
  objects/             the content-addressed blob directory (§5)
    ab/cd/abcd…         a body, at objects/<h[0:2]>/<h[2:4]>/<hash>
  index.db             the search index, when one is built (SEARCH.md)
  index.lock           its indexer lock
```

A directory is a pimdir store if and only if it contains a pimdir.db whose `store_meta.format` is `'pimdir'`. The lock files are empty, created by the first handle that takes one, and hold no state.

The index is derived and droppable. No other file belongs in the directory; an implementation MUST ignore a file it does not own, and the collector (§5) walks objects/ only.

## 4. The database

### 4.1 Requirements

- The database MUST be a SQLite database named pimdir.db.
- Implementations MUST require **SQLite ≥ 3.37**, for `STRICT` tables and `DROP COLUMN`. Every table MUST be `STRICT`, so column types are enforced across implementations.
- `PRAGMA foreign_keys = ON` MUST be set per connection.
- `PRAGMA journal_mode = WAL` is RECOMMENDED for a local store; see §8 for a network filesystem.

### 4.2 Schema version

The schema version is `PRAGMA user_version`, mirrored in `store_meta.version`. The two MUST agree; a store where they disagree is corrupt.

Version 1 is [migrations/storage/0001_init.sql](./migrations/storage/0001_init.sql). While this part is `draft`, version 1 is edited in place (§6) and `user_version` stays `1`; a store at any other version, or created by an earlier draft, is recreated rather than migrated.

### 4.3 Tables

The canonical schema is migrations/storage/0001_init.sql, which is normative. This section is its prose companion.

- **`store_meta`** (one row): `format`, `version`, `hash_algo` (`blake3` RECOMMENDED, or `sha256-128`), `created_at`, and the counters `next_seq` (§9.1), `next_change` and `purges` (§4.5).
- **`collections`**: `id`, `account` (§9.2), `kind` (the media type every item shares), `name`, `parent` (hierarchy by reference), the presentation columns `color`, `description`, `sort_order`, the cross-source `conflict` policy, `generation` (§12) and `changed` (§4.5).

  Every foreign key onto `id` is `ON UPDATE CASCADE`, so a rename keeps its contents (§14); `ON DELETE` is `CASCADE`, `SET NULL` for `parent`.
- **`sources`**: one row per source syncing a collection, keyed `(collection, source)`, carrying its `checkpoint`.
- **`objects`**: `hash` (primary key, under `hash_algo`), `size`, `refcount` (§5, §7). The bytes live in the blob file.
- **`items`**: the shared truth of one item, keyed `(collection, link_id)`: `seq` (§9.1), `flags` (a JSON array), `object_hash`, `sort_key` (§9.3), `level` (0 probed, 1 meta, 2 full), the cross-source state `deleted`, `conflicted`, `conflict_object`, the retention stamps `retained_at`, `retained_by` (§11), and `changed` (§4.5).
- **`mail_summary`**, **`contact_summary`**, **`event_summary`**, **`task_summary`**, **`journal_summary`**: one table per kind, at most one row per item, keyed `(collection, link_id)`, cascading with the item, referencing no object. Their columns are Annex A's, so a writer that disagrees with the shape fails at the write.
- **`item_address`**: the people an item names, keyed `(collection, link_id, role, position)` (Annex A.6). One table across every kind, so "everything about this address" is one seek on `item_address_by_address`.
- **`probes`**: the handles a source enumerated whose identity is not read yet, keyed `(collection, source, handle)`, with the flags reported (SYNC.md §3).
- **`bindings`**: one source's binding of an item, keyed `(collection, link_id, source)`: the `handle`, the sync base (`base_flags`, `base_object`, `base_revision`, `base_present`), the `shared_object` last agreed with the item, and the conflict triple `conflicted`, `conflict_revision`, `conflict_object`. A handle is bound once and never repointed, and names one item per source (§10): `bindings_by_handle` is unique.
- **`queue`**: the action queue (§15): `id`, `created_at`, `producer`, `collection`, `action`, `payload`, `object_hash`, `attempts`, `error`.

An item plus one binding per source is the whole model. Single-source is the N=1 case; N≥2 adds only `deleted`, a removal that lingers until every source has dropped it.

Flags stay a JSON array: the set is small and `json_each` answers an ordinary query. A flag predicate index is the search part's (SEARCH.md).

### 4.4 Queries

The named, parameterised statements servicing §14 live under [queries/storage/](./queries/storage/), one file per statement named after it, sorted by the profile that runs it: read/ is the reader's (§14.1), queue/ the producer's (§15.1), owner/ the rest, an owner running all three. An implementation reads them by listing its directories. A file's leading comment says what the statement alone cannot; the rules are this document's.

An implementation SHOULD use them verbatim and MAY substitute an equivalent preserving §7's invariants. The search index's statements are under queries/search/ on the same terms.

### 4.5 The change feed

`items.changed` and `collections.changed` hold the value of `store_meta.next_change` the row took when it last moved. The counter only increases. `PRAGMA data_version` says that something committed; the feed says what.

Triggers in the canonical DDL maintain the stamps, so no writer plumbs them. An insert takes the next stamp; an update takes one only when a column a reader can observe moved. A summary or address row has no stamp: a writer changing one under an unchanged item MUST run `stamp_item` in the same transaction.

A deleted row cannot carry a stamp, so a purge counts in `store_meta.purges`. A consumer records `(next_change, purges)` from `load_change_cursor`, folds `list_items_changed_since` and `list_collections_changed_since` on its next look, and reconciles its keys against the store only when `purges` moved.

A renamed collection stamps the new id and nothing under the old one, which a consumer keyed on the old id treats as a purge.

## 5. The blob store

Bytes live under objects/, one file per hash, sharded `objects/<hash[0:2]>/<hash[2:4]>/<hash>`. The name is normative: two writers naming one body differently stop deduplicating and stop finding each other's blobs, and nothing reports it.

- The digest is over the raw bytes, whole.
- **`blake3`** is BLAKE3 at its default 32-byte output, a 52-character name. **`sha256-128`** is the leading 16 bytes of SHA-256, a 26-character name, for a runtime with SHA-256 and no BLAKE3. Which one a store uses is `store_meta.hash_algo` and MUST NOT be inferred from a name's length.
- The alphabet is RFC 4648 §6 base32, lowercased, unpadded. The shards are the first two and next two characters of that name.
- §16's vectors are what an implementation checks itself against; the empty body is a real object.

**Write** is atomic: a period-prefixed temporary file in the shard directory, `fsync`, `rename`, then `fsync` the directory. Without the directory sync a power loss can leave a committed row pointing at a body that never arrived.

**Reference counting**: `objects.refcount` MUST equal the number of pointers at the hash across `items.object_hash`, `items.conflict_object`, `bindings.base_object`, `bindings.conflict_object` and `queue.object_hash`, maintained in the same transaction as the writes.

`bindings.shared_object` names a body and MUST NOT be counted: it is compared for equality and never read, and counting it would pin every body a source ever agreed with.

**An unreferenced object is not a deleted one.** A write MUST NOT delete a row at refcount zero nor unlink its blob: a consumer MAY index a body in one batch and attach it in a later one.

**The collector** is one operation, run when asked. It deletes the rows at `refcount <= 0` (`list_garbage_objects`, `delete_garbage_objects`), then walks the blob directory and unlinks every file no row names (`object_exists`, a point lookup per file), orphans from crashes included. A period-prefixed temporary file belongs to a writer and MUST be left alone.

It MUST hold the owner lock and take the staging lock exclusively (§8), which is what proves no writer is between a body and its row. Running it is the owner's to schedule; a store that never collects grows without bound. A store MAY `recompute_refcounts` first (§7).

## 6. Migrations

Schema evolution is ordered, forward-only SQL under migrations/storage/, named NNNN_description.sql. The runner MUST read `PRAGMA user_version` (0 for a fresh database), then for each migration above it, in order, open a transaction, run the script, set `user_version`, commit; a failed script rolls back and stops.

There are no down-migrations. An implementation meeting a newer or corrupt store MAY rebuild from the blobs and a full re-sync, which MAY lose un-pushed local mutation: a migration MUST preserve item and binding state, and rebuild is a last resort.

**While this part is `draft`** a schema change MAY be folded into 0001_init.sql, `user_version` staying `1`. A store from an earlier draft is then not detectably out of date, so an implementation MUST either reconcile the shape on open (`ALTER TABLE … ADD COLUMN`, guarded by `PRAGMA table_info`) or refuse the store with a message; failing a later query is not acceptable.

A reconciled column MUST be backfilled where `NULL` contradicts the existing rows, in the same transaction: `bindings.shared_object` from the item's `object_hash` (`backfill_shared_object`), or the first absorb files a source's own pending edit as a divergence.

A constraint is reconciled by a table rebuild (create, copy, drop, rename) in the same transaction, and four things about it are normative: repair the data first (`recompute_refcounts` for §7's floor); `PRAGMA foreign_keys` off for the rebuild and `PRAGMA foreign_key_check` before commit; recreate the indexes, which the drop took; detect the constraint from `sqlite_schema`, since `table_info` never reports one.

## 7. Integrity

- A store is self-checking: `PRAGMA integrity_check`, plus recomputing an object's hash against its row and file name.
- The refcount invariant (§5) and the foreign keys are the structural invariants. `recompute_refcounts` settles every object in one grouped pass over the five pointer columns, linear in the pointers, counting zero for an object nothing names.
- `objects.refcount` carries `CHECK (refcount >= 0)`, checked per statement: a double release fails at the release rather than as a foreign-key failure on every later write.
- The order of trust is blob bytes over database row: a row whose hash disagrees with its body is repaired from the body.

## 8. Concurrency and ownership

At most one process on one host owns pimdir.db at a time, and only the owner mutates collections, items, bindings, sources and objects, the §15 enqueue excepted.

An owner MUST hold an exclusive advisory lock on owner.lock for as long as it owns the store. The lock belongs to the open file, so a crashed owner leaves nothing to recover. An owner that cannot take it MUST fail immediately, naming the store, and never wait: what to do next is the caller's. The database's busy timeout is unaffected.

The rule is about processes: one owner opening several handles takes the lock once and shares it. The lock excludes other processes and nothing inside its own, so an owner MUST serialise its own collector against its own writers, and MUST release and retake the role as one operation, or it locks itself out.

Two lesser roles exist, both local-host only:

- **Readers** open read-only and see consistent WAL snapshots, any number at once, while an owner runs. A reader MUST NOT take either lock.
- **Producers** perform the §15 enqueue transaction and nothing else, and MUST NOT assume when the owner applies it. A producer MUST hold the staging lock on objects.lock shared across the blob write and the enqueue that pins it: that is the window a collector must not run inside.

On a network filesystem neither SQLite's locking nor advisory locks are reliable. Such a store MUST be owned by exactly one process on one host, SHOULD be enforced single-instance with a lease, and MUST use rollback-journal mode or `PRAGMA locking_mode = EXCLUSIVE`, never WAL's shared memory or `mmap`.

## 9. Identity and dedup

Four identifiers, kept distinct:

- **handle**: the backend's per-collection id, never the cross-collection key.
- **link id**: the item's key in its collection (`items.link_id`), internal: a consumer keys reads and edits by `seq`.
- **hash**: content state and blob key.
- **seq**: the store-global public id (§9.1).

Annex A derives the **hint**; this section assigns the key. A writer SHALL assign `link_id` from the first branch that applies:

- the content states no usable hint: the kind's fallback (`alt:` for a message, `hash:` for a DAV resource);
- the hint is free in this collection: the hint verbatim;
- this source already binds the hint under another handle: a **minted** key, `dup:`, the hint, `#` and that handle, concatenated verbatim (`dup:abc@host#1174`). A `KeepBoth` fork (SYNC.md §5) is minted the same way over its provisional handle.

The minted form needs no digest, is deterministic, and is prefixed like the fallbacks, so a prefixed id is never pushed as a protocol identity. It is opaque: a reader MUST NOT parse it and a store MUST NOT rewrite it, since rewriting would change a `seq` a consumer has shown.

Deduplication keys on **hash**: one body in two collections is stored once. Merging keys on the **hint**, conservatively: a missed dedup is harmless, a wrong merge hides data. `lookup_objects` (§14) is keyed on the assigned link id, so a minted item fetches its own body.

A writer-derived key (`alt:`, `hash:`, `dup:`) carries no identity: two messages with equal subject, date and sender and no `Message-ID` share an `alt:` key and may be two bodies. Such a key MUST NOT match in `lookup_objects` and MUST NOT share a `seq` (§9.1).

A `hash:` key names bytes, so a UID-less card edited on its server changes key under the same handle: the old item is retained, the new one is ordinary, and every other source sees a delete and an add (SYNC.md §3).

All four are store-wide, accounts included (§9.2). An identity or a body in more than one collection is a fact the store reports (`list_link_placements`, `list_object_placements`), never a merge it performs.

### 9.1 The public id (`seq`)

`items.seq` is a small integer a consumer shows and accepts wherever it would take a link id. One `link_id` keeps one `seq` in every collection and account it is filed in, drawn from `store_meta.next_seq` (`seq_for_link_any`, else `bump_next_seq`). It is assigned once, only increases, and is never reused. A consumer reads and edits by `(collection, seq)`, which is unique.

A minted key, an `alt:` key and a `hash:` key each draw their own `seq`: a derived key restates nothing the content carries. The item holding the bare hint keeps the shared one, so one message in two mailboxes shows once and two resources one collection holds show twice.

### 9.2 Accounts

`collections.account` is a grouping key, `NULL` in a single-account store. `collections.id` stays unique store-wide, so an owner filing two accounts namespaces their ids (`work/INBOX`) and records the account so a reader filters on a column rather than a prefix.

The account scopes nothing: link ids, hashes and `seq`s keep their store-wide meaning. What multiplicity across accounts means is the interface's: a mail view lists the placements, a contact view may offer a merge.

Ownership (§8) and sources (§10) are unchanged, so an owner syncing accounts in parallel processes MUST give each its own store. A `link_id` collision between unrelated servers is answered by conservative merging: a consumer that cannot tolerate a false pairing compares bodies.

The store records nothing else about an account: no credentials, no endpoints. It learns an account from its collections, so an account with none is not listed. An owner that namespaces MUST keep the separator out of account ids, since `a` with `b/c` and `a/b` with `c` spell the same string, and SHOULD choose an id that never changes.

### 9.3 The sort key

`items.sort_key` is one TEXT column giving an item's position in its collection's natural order, since neither a link id nor a `seq` is an order.

- The store defines the column, the ordering and the paging; Annex A defines what a key holds per kind.
- It is **written, never derived**: the store MUST NOT parse a summary to obtain it.
- Byte order is the order (`BINARY` collation), so a timestamp is RFC 3339 UTC at fixed width with the `Z` designator.
- `''` means unknown, the default: last in a descending listing, first in an ascending one.
- `seq` breaks ties, so a page over `(sort_key, seq)` is total.
- `set_sort_key` restates a key without refetching; a `write` MUST leave an existing key alone unless it carries a new one.

Paging is a seek on `items_by_sort`, not a scan. A key is presentation, not sync: a wrong one mis-sorts and loses nothing.

## 10. Sync model

A shared item holds the merged truth; a binding per source records the base last agreed with that source. The sync part (SYNC.md) derives what changed on each side and reconciles.

A binding records two agreement points and a store MUST keep both: `base_object`, what the source last agreed with its remote, moved only by a sync, so a pending push stays derivable; `shared_object`, what it last agreed with the shared item, moved by every absorbed upsert. Measuring the cross-source axis from the sync base reads a source's own pending edit as another source's.

`level` is the tier an item reached, a claim; `object_hash IS NOT NULL` is the fact of a body, and a remote content change drops the body while the level stays. `deleted` carries a removal until every source has dropped it, and the item is then retained (§11).

A handle enumerated but not yet named is a `probes` row, not an item. It becomes an item and a binding in the transaction of the fetch that names it.

Two divergences are recorded and are not the same fact: `items.conflicted` and `items.conflict_object`, two sources editing the shared body differently; `bindings.conflicted`, `conflict_revision` and `conflict_object`, one source diverging from its own remote. A store MUST persist both independently.

A binding's conflict MUST be cleared when the sync writes any resolved state for it, releasing the pin its `conflict_object` held.

A write resolving an existing `(collection, link_id, source)` binding to a different handle SHALL be refused, recording no trace of the incoming handle. A rebind is licensed only by a drop of the bound handle in the same batch, with reason `Superseded` (a provisional handle an accepted add replaced) or `Rekeyed` (§12). A source holding one identity twice never reaches the refusal: the second copy resolves to a minted key (§9) and is stored as an item beside the first.

Two items is the report; the store picks no survivor and warns about nothing.

The other direction is a rebind too: a handle names one link id per source. A write resolving a bound handle to a different link id, a `hash:` key that changed under the same DAV resource (§9), SHALL retire the old binding first, in the same transaction, as a `Deleted` drop of that handle would (§11).

The unique index on `(collection, source, handle)` refuses a write that does not.

## 11. Retention

When an item's last binding vanishes the store retains the row rather than deleting it, and only an explicit purge removes it. A remote expunge therefore never destroys the local copy. The one exception is an identity another collection of the same account holds live: the item moved, or was filed twice, and nothing is lost by purging the row in the same transaction, the holder pinning the body. Retention is the terminal state of `deleted`: a retained row carries `deleted = 1`, no bindings, and a non-`NULL` `retained_at`. It is unconditional; how long to keep and when to sweep is the owner's schedule.

### 11.1 Requirements

- **Retire, do not delete** (`retain_item`): stamp `retained_at` and `retained_by`, keep `object_hash` so the body stays pinned.
- **A held identity is not kept twice**: when another collection of the same account holds the link id live (`held_elsewhere`), `retain_item` is followed by `purge_item` on the seq `retained_item` gives and `release_pins`, in the same transaction, and the purge counts (§4.5).
- **Stamped by SQLite**: `retained_at` is written by the statement; the cutoff of a purge is the caller's parameter.
- **Hidden from the sync seam**: `load_items` filters `retained_at IS NULL`, or the next run re-uploads every retained row. `delete_items` spares them for the same reason.
- **Hidden from the reads**: a retained row is a tombstone under §14.1's live-only rule; `list_retained_page` and `count_retained` are the trash view.
- **Purge is the only true delete**: `purge_item` and `purge_retained_before`, both guarded on `retained_at IS NOT NULL`, both `RETURN` the pinned hashes for `release_pins` in the same transaction. The bodies fall to the collector.
- **A reappearing link id revives** (`retained_item` then `revive_item`): stamps cleared, `deleted` back to 0, content adopted, the pins the retained row held released, `seq` kept. One branch serves a source-side resurrection and a queued `add`.
- `retained_by` is diagnostic; a retained item has no binding and pushes nothing.

### 11.2 Purging

`purge_item(collection, seq)` empties one item; `purge_retained_before(cutoff)` every item retired before an RFC 3339 instant, store-wide, the owner computing the cutoff from its own policy. A cutoff of now reproduces terminal deletion. `retained_bytes()` reports what retention holds. Either purge counts in `store_meta.purges` through the delete trigger (§4.5).

## 12. Collection generation

`collections.generation` is the handle-space epoch. The owner MUST bump it (`bump_generation`) in the transaction of the rebuild that re-learns a collection's handles (an IMAP `UIDVALIDITY` change), and readers deriving epoch-dependent protocol values read it with `load_generation`. Ordinary syncs, full resyncs and content changes MUST NOT bump it.

A rebuild's batch drops the old spine and upserts the same items under their new handles, so a binding's handle does move. What licenses it is the drop with reason `Rekeyed` (SYNC.md §8), per handle; a duplicate in the same batch is still refused. The batch carries no op for the bump: a `Rekeyed` drop is what tells the store the batch is a rebuild, and the store bumps in the transaction applying it.

## 13. Encodings

Two implementations produce byte-identical stores only with identical encodings. These are normative.

- **`level`** (INTEGER): `0` probed, `1` meta, `2` full.
- **`deleted`, `conflicted`** (INTEGER): `0` or `1`.
- **`conflict`** (TEXT, on a collection): `'manual'`, `'prefer-incoming'` or `'prefer-existing'`.
- **`flags`, `base_flags`** (TEXT): a JSON array of raw flag strings sorted by code point (`["$flagged","\\Seen"]`). `NULL` is unknown, `'[]'` is known-empty. The same on `probes.flags`.
- **`object_hash`, `base_object`, `conflict_object`** (TEXT): a hash under `store_meta.hash_algo`, or `NULL`.
- **`refcount`** (INTEGER): the pointer count of §5, `>= 0` by constraint; `0` is a meaningful, collectable count.
- **`link_id`** (TEXT): the hint verbatim, a kind fallback, or a minted `dup:<hint>#<handle>`; opaque.
- **`sort_key`** (TEXT): §9.3; `''` unknown; a timestamp as `2026-08-01T10:00:00Z`. The one column exempt from byte-identity: a zoned time resolves through a time zone database two writers may hold at different versions, and a wrong key loses nothing.
- **`changed`** (INTEGER, on `items` and `collections`): the stamp of §4.5, `0` before the feed existed; `next_change` and `purges` (INTEGER, on `store_meta`) its counters.
- **The summary columns**: Annex A's, decoded or verbatim as it says, an instant with the `Z` designator, `NULL` for absent and unknown unless it says otherwise.
- **`role`, `address`, `position`** (on `item_address`): a role of Annex A.6, the canonical addr-spec, and the 0-based document order within the role.
- **`base_revision`** (TEXT): an opaque etag or modseq, or `NULL`.
- **`conflict_revision`, `conflict_object`** (on a binding): the remote revision and body observed when the binding was marked conflicted. A binding that is not conflicted MUST NOT carry either.
- **`shared_object`** (TEXT, on a binding): the shared body last reconciled against (§10), `NULL` until the source has folded once; never counted (§5).
- **`created_at`, `retained_at`** (TEXT): `strftime('%Y-%m-%dT%H:%M:%fZ','now')`, stamped by SQLite (`init_store_meta`, `enqueue_action`, `retain_item`). Every instant the format fixes is UTC with the **`Z` designator**, never `+00:00`, which sorts apart from it.
- **`retained_by`** (TEXT): the source whose removal retired the item, diagnostic.
- **`checkpoint`** (BLOB): opaque cursor bytes, or `NULL`.
- **`base_present`** (INTEGER, on a binding): whether a base exists. A base is present iff `base_present` is 1 or any base column is non-`NULL`; a writer MUST set the column and a reader MUST accept either witness.
- **`action`** (TEXT): `'add'`, `'set-flags'`, `'remove'`, `'move'`, `'copy'`, `'update'` (§15.3), or an application's own kind, skipped by an owner that does not know it.
- **`payload`** (TEXT): versioned JSON with a leading integer `v`. **`error`** (TEXT): `NULL` while pending; set when parked.
- **`generation`** (INTEGER): the epoch of §12, starting at 1.

## 14. Operations

A store is opened as one source. `load` projects the shared items into that source's placements; `write` folds its changes back. The statements are §4.4's, bound with §13.

- **`load(collection, scope)`**: `load_items`, `load_bindings`, `load_conflict`, projected for the source (SYNC.md §3), plus `load_probes` and `load_checkpoint`. The scope (SYNC.md §10) is a floor: `All` reads the collection; `Links` reads `load_items_by_link` and `load_bindings_by_link` for the link ids named; `Handles` resolves each handle with `link_for_handle` and reads the same two, a handle nothing binds being a probe. A `Created` placement's origin is `origin_for_link` and a `Tombstone` placement's destination `destination_for_link` (SYNC.md §3). The probes of a `Handles` load are `load_probes_by_handle`, of the others `load_probes`. A store MAY return more than the scope names and MUST NOT return less.
- **`lookup_objects(links)`**: `:links` a JSON array of link ids, `:account` the caller's own (§9.2): across collections a link id is one body downloaded once, across accounts it is not a fact. A writer-derived key never matches (§9).
- **`write(ops)`** runs as one transaction:
  1. A `StoreObject` carries the index row and optionally the bytes. With bytes, write the blob first (§5), then `store_object`; without, the body is already at its sharded path, streamed there by the consumer. The blob write MAY precede `BEGIN` and SHOULD for a body of any size; the writer's lock (§8), not the file's age, keeps a collector out of the window.

     A `SetCheckpoint` runs `ensure_collection` then `upsert_checkpoint`.

     Placement upserts and drops are merged into the shared items and bindings, `set_conflict` carrying the collection's policy. The reference form is the **diff**:

     `load_items_by_link`, `load_bindings_by_link`, the kind's `load_<kind>_summaries` and `load_addresses_by_link` bound to the batch's link ids, each dropped handle resolved with `link_for_handle` and each upserted handle likewise, a handle bound to another link id retiring that binding first (§10), then `insert_item`, `insert_binding`, `update_item`, `update_binding`, `delete_binding` for a binding a `Deleted` drop removes, and `delete_item_bindings` with `retain_item` for an item the result no longer holds, purged at once when `held_elsewhere` says the identity moved (§11). `update_binding` carries no handle: a rebind is refused (§10) except through §12's rebuild.

     A load-all / replace-all (`delete_items`, then every row inserted) persists the same state and MAY be used, but stamps the whole collection on every sync (§4.5).

     A named placement carries its summary and addresses, derived by the writer under Annex A and written with the item (`upsert_<kind>_summary`, `replace_addresses`, `insert_address`). An unnamed one is a probe (`upsert_probe`), dropped (`delete_probe`) in the transaction that names it. An item left with no binding is retained (§11).
  2. Settle the refcount of every object the batch touched: `recompute_refcounts`, or `adjust_refcount` by the batch's net change, keeping the recompute for repair (§7). A batch that stored or dropped no object MAY skip this.
  3. Commit. The batch reclaims nothing (§5).

The queue adds **`enqueue`**, **`drain`** and **`cancel`** (§15); retention adds **`purge`** and **`purge_retained_before`** (§11.2), both reporting rows and never bytes. **`collect_garbage()`** is §5's collector, reporting the rows, files and bytes it freed.

A collection's `kind` is declared, never derived: `set_collection_kind(collection, account, kind)` sets it, `load_kind` reads it, and `ensure_collection` inserts an empty kind it MUST NOT overwrite. The account binds the same way; `set_collection_account` re-accounts a collection, `load_account` reads it.

**`rename_collection(collection, new_id)`** is the only safe way to change an id: every foreign key onto `collections(id)`, and `bindings`' key onto `items(collection, link_id)`, cascades, so items, bindings, sources, queue rows and children follow in one statement. Deleting and recreating the row cascades the delete instead.

A bare `UPDATE` is refused under `NO ACTION`, and with `PRAGMA foreign_keys` off the rename cascades nothing. An account rename is one `rename_collection` per collection plus `set_collection_account`, in one transaction.

### 14.1 Reading the store

A **reader** (§8) opens read-only and projects the store as a local backend. Reads are kind-agnostic where they can be, keyed by `seq`, and named after their statement.

- **`list_collections()`**, **`list_collections_by_account(account)`** (`NULL` selects a single-account store's), **`list_accounts()`** (accounts owning at least one collection, not a roster).
- **`list_items_page(collection, after, limit)`**: a keyset page in link-id order, the sweep that sees every item once; `''` starts from the beginning.
- **`list_items_page_asc`**, **`list_items_page_desc`** `(collection, after_key, after_seq, limit)`: the natural order (§9.3), cursor `(sort_key, seq)`; descending, a `NULL` cursor is the first page.
- **`list_mail_page_desc`**, **`list_contacts_page_asc`**, **`list_events_page_asc`**, **`list_tasks_page_asc`**, **`list_journals_page_asc`**: the same page joined with the kind's summary; **`get_mail`**, **`get_contact`**, **`get_event`**, **`get_task`**, **`get_journal`** one item. A mixed calendar merges its three pages on `(sort_key, seq)`; `component_of` says which table holds an item.
- **`get_item(collection, seq)`**, **`count_items(collection)`**, **`seq_by_link(collection, link_id)`**.
- **`list_link_placements(link_id)`**, **`list_object_placements(hash)`**: every live placement of one key, or one body, with collection and account. The first pairs by key, so a minted copy is paired with its twin by the body read alone.
- **`list_address_placements(address, role)`**: every live placement naming one address, `role` `NULL` for any: the person axis. **`list_domain_placements(domain, role)`**: the same for a domain, by a scan.
- **`list_items_changed_since`**, **`list_collections_changed_since`**, **`load_change_cursor`**: the feed (§4.5).
- **`list_retained_page(collection, after, limit)`** (cursor on `seq`, `0` starts), **`count_retained`**, **`retained_bytes()`**: the trash view (§11).
- **`list_sources()`**, **`list_conflicted_bindings(account)`** (the bindings awaiting a decision with the three bodies the divergence is between, answered by index, never by paging), **`list_item_bindings(collection, link_id)`** (where one item lives per source), **`link_for_handle`** and **`handle_for_link`**, **`load_kind`**, **`count_probes`**.

Three rules bind every read:

- **Live only.** A tombstone (`deleted = 1`) is never presented as live; the retained reads are the exception and present their rows as retained.
- **Level-aware.** `level` says the tier reached, `object_hash` whether a body is there. A reader renders a list from the summary and treats an absent body, or a blob file gone under a purge, as not yet hydrated, never as an error.
- **Snapshot-consistent.** A reader sees a WAL snapshot and may run beside the owner. It detects change by `PRAGMA data_version` or the feed, and MAY overlay pending actions (§15.4).

## 15. Action queue

Only the owner mutates (§8), yet other processes originate mutations. The `queue` table is their write door: a **producer** appends an action, the **owner** applies it. Actions address collections and public ids, so the six kinds serve every domain, and the kind is an open string beside a versioned payload.

### 15.1 Producing

A producer enqueues in one transaction: `ensure_collection`, at most one `store_object` when the payload names a body (the blob written first, §5), then `enqueue_action` carrying the hash in `object_hash` so the body is pinned. `created_at` is stamped by the statement. This is the only write a non-owner may perform, and a producer MUST NOT rely on any application deadline.

### 15.2 Applying

The owner drains each collection's pending actions in ascending `id` (`list_queued_collections`, `load_pending_actions`). An action is applied and its row deleted in one transaction, which spans no network I/O. `claim_action` runs **first** in it: the pending list is read outside any transaction, so a row it names may be gone by the time its turn comes, cancelled (§15.5) or applied by another handle of the owning process, and a claim that deletes nothing means the row is not this transaction's to apply.

A failed action is retried (`bump_attempts`). One the owner judges permanently unappliable is parked (`park_action`): the attempt counted, `error` set, the action skipped, later ones proceeding, read back with `load_parked_actions` and never silently deleted.

A failure of the store itself (a refused rebind, a constraint) is permanent for the row and MUST park it. Only a failure of the environment (the database busy, a body unreadable) is retried, and neither MUST stop the rows behind it.

**Skipping is not parking.** An owner that does not recognise a kind, or lacks the capability it needs, SHALL leave the row pending and untouched, `error` `NULL`, `attempts` unbumped, and SHALL NOT block later actions on it. A drain has three outcomes per row: applied, parked, skipped.

### 15.3 Actions

Existing items are addressed by `seq`. At `v: 1`:

- **`add`**: `{ "v": 1, "link_id": …?, "flags": […], "object": hash, "handle": …? }`. Creates an item staged as a local creation to push; the owner derives its summary and addresses from `object` (Annex A). A duplicate `link_id` (`live_item_for_link`) parks the action unless the row holding it is retained, which revives it (§11): a source's duplicate is minted (§9), a producer's is a mistake worth reporting.
- **`set-flags`**: `{ "v": 1, "seq": n, "flags": […] }`. Replaces the set, absolutely.
- **`remove`**: `{ "v": 1, "seq": n }`. Already absent is success; an item the draining source does not bind is skipped (§15.2), the source that binds it applying the row.
- **`move`**: `{ "v": 1, "seq": n, "to": collection }`. `copy` is the same shape without the removal.
- **`update`**: `{ "v": 1, "seq": n, "object": hash }`. Repoints a mutable item's body; the owner re-derives its summary and addresses.

An application MAY carry a kind of its own, versioned the same way; a mail submission is the worked example. The store owes it append order, blob pinning and the skip rule.

### 15.4 Reading the queue

A reader MAY overlay a collection's pending actions (`load_pending_actions`) for read-your-writes.

### 15.5 Cancelling and acknowledging

`cancel_action` removes a pending or parked row by request, returning its pin: an operator withdrawing it, or the performer of a capability-bound intent acknowledging it. It is an owner write and MUST run in one transaction with `release_pins` on what it returned. An applied action cannot be cancelled: application deleted its row.

An intent whose effect is not a store mutation is therefore at-least-once, and deduplicating is the performer's.

## 16. Test vectors

A schema mismatch fails a query; a body named differently, a summary derived differently or a key sorted differently fails nowhere. vectors/ is therefore part of the format:

- **vectors/objects.json**: bodies to object names under both `hash_algo` values, with shard paths, and the RFC 4648 §10 base32 vectors.
- **vectors/summaries.json** and **vectors/fixtures/**: bodies to the `link_id`, summary row, address rows and `sort_key` Annex A produces, the hedged cases, the encodings that split earlier writers, and the minted keys of §9.
- vectors/sync/ and vectors/search/ belong to the other parts.

An implementation **MUST** pass objects.json: two stores naming bodies differently cannot share a blob directory. It **MUST** pass summaries.json for each kind it writes, the minted and the `hash:` keys they give included. A consumer MUST compare parsed structures, never JSON text. The values are authored from the prose, never from an implementation.

An implementation that vendors vectors/ MUST record their digests and re-check them against this repository in CI.

## Annex A. Summaries (normative)

What a writer derives from an item before its row reaches the store: the identity hint §9 keys on, the row of the kind's summary table, the `item_address` rows and the `sort_key` (§9.3). The store parses no body; the tables fix the shape and vectors/summaries.json the values.

A derivation is made from the body, or from a server-side summary (an IMAP `ENVELOPE`) where the kind has a cheap tier. Where a kind has both, the two MUST agree byte for byte.

### A.0 Common rules

- **Decoded**: RFC 2047 words and RFC 2231 parameters decoded, vCard and iCalendar text unescaped (RFC 6350 §3.4, RFC 5545 §3.3.11), lines unfolded. A property splits on the first unquoted colon (RFC 6350 §3.3).
- **Verbatim**: the value bytes as the body carries them, unfolded.
- Invalid UTF-8 is replaced, never refused.
- A `NOT NULL` column is `''` when the property is absent; every other column is `NULL` when absent or not examined, unless the kind says otherwise.
- An instant is RFC 3339 UTC at seconds precision with the `Z` designator.

### A.1 `message/rfc822`

| Column | Derivation |
| --- | --- |
| `message_id` | the bare `Message-ID` (RFC 5322 §3.6.4), angle brackets stripped; `NULL` when absent or unparseable |
| `in_reply_to` | a JSON array of the `In-Reply-To` ids, bare, in document order; `'[]'` when absent |
| `subject` | `Subject`, decoded; `''` when absent |
| `sender` | the first `From` address, canonical (A.6) |
| `sender_name` | its display name, decoded |
| `date` | `Date` as an instant; `NULL` when unparseable |
| `size` | the raw octets, or `RFC822.SIZE` at the `Meta` tier |
| `attachment` | `1` when a part carries `Content-Disposition: attachment`, `0` when the parts were walked and none does, `NULL` when they were not walked |

**Hint**: `message_id`, else `alt:` followed by the decoded subject, the `date` column and the `sender` column joined by `|`, each empty when absent. **Addresses**: every `From`, `To`, `Cc`, `Bcc` under its role, in document order. `References` is the search part's (SEARCH.md §9). **`sort_key`**: the `date` column, or `''`; read descending.

### A.2 `text/vcard`

| Column | Derivation |
| --- | --- |
| `uid` | `UID` verbatim |
| `fn` | `FN`, decoded; `''` when absent |
| `kind` | `KIND` lowercased (`individual`, `group`, `org`, `location`) |
| `org` | the first component of the first `ORG`, decoded |

**Hint**: `uid`, else `hash:` followed by the sixteen lowercase hexadecimal digits of the FNV-1a 64 digest of the bytes. A card resolves at `Full` only, carries no flags (`'[]'`), and is mutable: its revision moves while its key does not. **Addresses**: every `EMAIL` under `email`, canonical, with no name. **`sort_key`**:

`fn` lowercased by the Unicode simple lowercase mapping, locale-independent, then trimmed; read ascending, a nameless card first.

### A.3 `text/calendar`, `VEVENT`

**The item is the calendar object resource.** RFC 4791 §4.1 keeps the components sharing a `UID` in one resource, so a series and its `RECURRENCE-ID` overrides are one item, one blob, one key, and an override is a body edit. A connector to an instance-granular source MUST reassemble the set. A resource holds one component type, so its summary is one row in that type's table:

`event_summary`, `task_summary` (A.4) or `journal_summary` (A.5). A component with no table (`VFREEBUSY`, `VAVAILABILITY`) is an item with a body and no summary. A second resource under one `UID` is minted and kept (§9).

| Column | Derivation |
| --- | --- |
| `uid` | `UID` verbatim |
| `summary` | `SUMMARY` of the master (no `RECURRENCE-ID`), decoded; `''` when absent |
| `location` | `LOCATION`, decoded |
| `dtstart`, `dtstart_tzid`, `dtstart_value` | `DTSTART` verbatim, its `TZID`, and `date-time` or `date` |
| `dtend` | `DTEND` verbatim; a `DURATION` is not resolved |
| `recurring` | `1` with an `RRULE` or `RDATE` on the master, `0` when looked and none, `NULL` when not looked |
| `until` | the `RRULE`'s `UNTIL` verbatim |

Times are verbatim with their parameters, never resolved: a reader with a time zone database re-derives an instant, one without displays the wall time. The one resolved projection is the `sort_key`. **Hint**: `uid`, else `hash:` on A.2's terms; mutable, no flags. **Addresses**: `ORGANIZER` and every `ATTENDEE` under their roles, `mailto:` stripped, canonical, the `CN` parameter as the name.

**`sort_key`**: the master's `DTSTART` as an instant, read ascending.

A UTC date-time is taken as is; a zoned one resolves through the resource's own `VTIMEZONE`, an ambiguous wall time taking the offset in effect before the transition and a nonexistent one the offset after it (both the numerically greater offset); a zone that will not resolve reads as floating; a date-only value reads as `T00:00:00Z`; a floating date-time reads as UTC.

A series keys on its first occurrence, which `until` bounds for a reader that must expand it (SEARCH.md §7). Nothing parseable keeps `''`.

### A.4 `text/calendar`, `VTODO`

`task_summary` carries `uid`, `summary`, `dtstart` with its parameters, `recurring` and `until` on A.3's terms, and:

| Column | Derivation |
| --- | --- |
| `due`, `due_tzid`, `due_value` | `DUE` verbatim, its `TZID`, and `date-time` or `date` |
| `status` | `STATUS` uppercased verbatim |
| `completed` | `COMPLETED` verbatim |
| `percent` | `PERCENT-COMPLETE` as an integer |

**`sort_key`**: `DUE`, else `DTSTART`, as an instant on A.3's rules (RFC 5545 §3.8.2.3); `''` when neither.

### A.5 `text/calendar`, `VJOURNAL`

`journal_summary` carries `uid`, `summary` and `dtstart` with its parameters on A.3's terms. **`sort_key`**: `DTSTART` as an instant, or `''`.

### A.6 Addresses

`item_address` holds every person an item names, one row per address per role, in document order within the role: `from`, `to`, `cc`, `bcc` for mail, `email` for a card, `organizer` and `attendee` for a calendar object.

The **canonical address** is the addr-spec alone, display name, comments, angle brackets and `mailto:` removed, lowercased whole. RFC 5321 §2.4 makes the local part case-sensitive and practice does not. A value that is not an addr-spec is kept lowercased as it is. The **name** is the display name decoded (a mail phrase, an `ATTENDEE`'s `CN`), or `NULL`; a card's addresses have none.
