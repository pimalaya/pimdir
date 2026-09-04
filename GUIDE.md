# Pimdir implementation guide

Status: informative

The procedures an implementation runs, in the order it runs them, naming the statements under queries/ and the vectors under vectors/ at each step. This document restates the rules of [STORAGE.md](./STORAGE.md), [SYNC.md](./SYNC.md) and [SEARCH.md](./SEARCH.md) as steps and tables; it adds none, and where it and a part disagree the part wins. §n of a part is written STORAGE §n, SYNC §n, SEARCH §n. §9 to §12 run the engine, §15 the index; what either owes the store is in §5.

A reader new to the model starts with [OVERVIEW.md](./OVERVIEW.md).

## Contents

1. [Conformance checklist](#1-conformance-checklist)
2. [Opening a store](#2-opening-a-store)
3. [The migration runner](#3-the-migration-runner)
4. [Naming and writing a body](#4-naming-and-writing-a-body)
5. [The write transaction](#5-the-write-transaction)
6. [The collector](#6-the-collector)
7. [Retention and purge](#7-retention-and-purge)
8. [Collection configuration](#8-collection-configuration)
9. [The projection](#9-the-projection)
10. [A sync run](#10-a-sync-run)
11. [Upgrade, mutate, rekey](#11-upgrade-mutate-rekey)
12. [Absorbing a write across sources](#12-absorbing-a-write-across-sources)
13. [The queue](#13-the-queue)
14. [A reader](#14-a-reader)
15. [The indexer and the query client](#15-the-indexer-and-the-query-client)
16. [Running the vectors](#16-running-the-vectors)

## 1. Conformance checklist

Three profiles read or write a store, each a superset of the one before, and an implementation states which it meets. Most implementations are readers or producers; the owner, the engine and the index are large, and the reference implementation is there to be used for them.

A **reader** opens the store and lists it:

| Step | What | Where |
| --- | --- | --- |
| 1 | SQLite 3.37 or later, `PRAGMA foreign_keys = ON`, a read-only open, no lock | STORAGE §4.1, §8 |
| 2 | Decode the columns as §13 says | STORAGE §13 |
| 3 | Serve the reads from queries/storage/read/, live rows only, level-aware, snapshot-consistent | STORAGE §14.1 |
| 4 | Follow the change feed for anything derived from the store | STORAGE §4.5 |

A **producer** is a reader that appends actions:

| Step | What | Where |
| --- | --- | --- |
| 5 | Pick `hash_algo` from the store, name and write a body as §4 says under the staging lock; pass vectors/objects.json | STORAGE §5, §8, §16 |
| 6 | Enqueue in one transaction with queries/storage/queue/, a kind and a versioned payload as §15.3 says | STORAGE §15.1, §15.3 |

An **owner** is the one process that mutates the store:

| Step | What | Where |
| --- | --- | --- |
| 7 | `STRICT` tables and WAL on a local store; apply migrations/storage/ through the runner of §3 | STORAGE §4.1, §6 |
| 8 | Take the owner lock before any write; fail at once when it is held | STORAGE §8 |
| 9 | Run the write transaction of §5 for every batch, with queries/storage/owner/ | STORAGE §14 |
| 10 | Derive summaries, addresses and sort keys under Annex A for each kind written; pass vectors/summaries.json for that kind | STORAGE Annex A, §16 |
| 11 | Retain rather than delete, purge a moved or requested row only, collect only under both locks | STORAGE §5, §11 |
| 12 | Drain the queue with claim-first, park or skip as §13 says | STORAGE §15 |

An **engine** (SYNC) is an owner that reproduces every case under vectors/sync/. An **index** (SEARCH) adds SQLite 3.43 with FTS5, migrations/search/ and queries/search/, and every **query client** on it answers the cases under vectors/search/ alike.

Use the statements verbatim. Every one of them prepares against the canonical schema, which checks/schema.sh proves on every push, and a substitute is yours to keep equivalent under STORAGE §7's invariants.

## 2. Opening a store

**As the owner:**

1. Open owner.lock beside pimdir.db and take an exclusive advisory lock on the open file (`flock` or `fcntl`). If it is held, fail now, naming the store; do not wait.
2. Open pimdir.db. Set `PRAGMA foreign_keys = ON` and, on a local filesystem, `PRAGMA journal_mode = WAL`. On a network filesystem use rollback journal or `PRAGMA locking_mode = EXCLUSIVE` and never WAL or `mmap`.
3. Run the migration runner (§3). On a fresh database this also runs `init_store_meta` with the chosen `hash_algo`.
4. Read `load_store_meta`. Refuse the store when `format` is not `pimdir` or `version` disagrees with `PRAGMA user_version`.
5. Keep the lock open until the process gives up the store. Several connections in one process share the one lock; release and retake it as one operation, never in between.

**As a reader:** open pimdir.db read-only (`?mode=ro` in a URI), set `PRAGMA foreign_keys = ON`, take no lock. Detect change with `PRAGMA data_version` or the feed (§14).

**As a producer:** open read-write, take no owner lock, and perform nothing but the enqueue of §13 under a shared lock on objects.lock.

## 3. The migration runner

1. Read `PRAGMA user_version`; `0` is a fresh database.
2. List migrations/storage/NNNN_*.sql ascending. For every NNNN above the current version: `BEGIN`, execute the script, `PRAGMA user_version = NNNN`, `COMMIT`. A failure rolls back and stops.
3. While the store part is draft, version 1 is edited in place, so a store stamped `1` may still lack a column. Reconcile on open, in one transaction: for every column of the canonical schema absent from `PRAGMA table_info`, `ALTER TABLE … ADD COLUMN`, then backfill where `NULL` contradicts existing rows (`backfill_shared_object` for `bindings.shared_object`). Refusing the store with a message telling the operator to recreate it is the other permitted answer; failing a query later is not.
4. A missing constraint is reconciled by a table rebuild in the same transaction: repair the data first (`recompute_refcounts` before adding the refcount floor), `PRAGMA foreign_keys = OFF`, create the constrained table under a temporary name, copy, drop the old one, rename, recreate the table's indexes, `PRAGMA foreign_key_check`, commit, `PRAGMA foreign_keys = ON`. Detect the constraint from `sqlite_schema`, since `table_info` never reports one.

The index has no migrations: an index.db at another version, or with another tokenizer, is deleted and rebuilt (§15).

## 4. Naming and writing a body

**Name:**

1. Digest the raw bytes, whole: BLAKE3 at 32 bytes for `blake3`, the first 16 bytes of SHA-256 for `sha256-128`. The algorithm is `store_meta.hash_algo`, never guessed from a name's length.
2. Encode in RFC 4648 §6 base32 (`a` to `z`, `2` to `7`), lowercase, no padding: 52 characters for `blake3`, 26 for `sha256-128`.
3. The path is objects/ then the first two characters, then the next two, then the whole name.

Check the encoder against the `base32.cases` in vectors/objects.json before trusting anything else, then the digests and paths against its cases, the empty body included.

**Write:**

1. Create the shard directory if needed.
2. Write to a period-prefixed temporary file in that directory, `fsync` it.
3. `rename` it onto the final name. The name is the content, so an existing file is the same bytes and the rename is harmless.
4. `fsync` the shard directory. Without it the database commit can outlive the file's name.

A body may be written before the transaction that references it opens, and a body of any size should be: the writer's locks, not the file's age, keep the collector away from it.

## 5. The write transaction

One batch of `UpsertPlacement`, `DropPlacement { handle, reason }`, `StoreObject { hash, size, bytes? }` and `SetCheckpoint` (SYNC §10), applied in order.

1. For every `StoreObject` carrying bytes, write the body (§4). One carrying none is already at its path.
2. `BEGIN`.
3. `store_object` for every `StoreObject` (the refcount starts at zero and is settled in step 11).
4. `ensure_collection` for the collection, which inserts an undeclared row and never overwrites a declared one. Read the policy with `load_conflict`.
5. Resolve the batch's keys. Each `DropPlacement` names a handle: `link_for_handle` gives its link id; a handle nothing binds is a probe, `delete_probe`. Each `UpsertPlacement` carries a link id, or none for a probe (`upsert_probe`, and stop here for that placement).
6. Read what the batch touches and nothing else: `load_items_by_link` and `load_bindings_by_link` bound to a JSON array of the batch's link ids.
7. Merge each placement into its shared item and binding under SYNC §9 and §10, then persist the diff:
   - a new item: `seq_for_link_any` for a stated hint, `bump_next_seq` when it returns nothing or the key is derived (`alt:`, `hash:`, `dup:`), then `insert_item`; a retained row under the same key is revived instead, `revive_item`;
   - a new binding: `insert_binding`; a binding whose handle differs from the incoming one is a refused write unless a `Superseded` or `Rekeyed` drop for the old handle precedes it in the same batch;
   - a moved item or binding: `update_item`, `update_binding`, which carries no handle;
   - a named placement's summary and addresses, derived under Annex A: `upsert_<kind>_summary`, `replace_addresses` then one `insert_address` per row, and `stamp_item` when only those rows moved;
   - a `Deleted` drop of the item's last binding: `retain_item`, which stamps `retained_at` and keeps the body pinned; then, when another collection of the same account holds the link id live, `purge_item` and `release_pins`, since the item moved.
8. A `Rekeyed` drop anywhere in the batch makes it a rebuild: `bump_generation` for the collection, once, in this transaction.
9. `SetCheckpoint`: `upsert_checkpoint` for this source, last in the batch.
10. Never reorder the batch: a provisional handle superseded by an accepted one is two entries for one handle in one order.
11. Settle refcounts: `adjust_refcount` per hash by the batch's net change, or `recompute_refcounts` for the whole store. A batch that stored or dropped no object skips this.
12. `COMMIT`. Reclaim nothing: an object at refcount zero stays for the collector.

The stamps of the change feed are written by the schema's triggers; a writer never binds one.

A replace-all form, `delete_items` then every row inserted, persists the same state and stamps every row of the collection on every sync, which starves every consumer of the feed.

## 6. The collector

1. Hold the owner lock (§2) and take an exclusive lock on objects.lock. Both are needed: the first excludes other owners, the second excludes producers between a body and its enqueue.
2. Serialise against the process's own writers: the owner lock does not exclude a second connection in the same process.
3. Optionally `recompute_refcounts`.
4. `BEGIN`; `list_garbage_objects` (refcount at or below zero), `delete_garbage_objects`; `COMMIT`.
5. Walk objects/ and for every regular file ask `object_exists` for its name. Unlink a file no row names. Leave every period-prefixed file alone: it belongs to a writer mid-rename.
6. Report rows dropped, files unlinked, bytes freed.

Run it on a schedule of the owner's, and after a purge. A store that never collects grows without bound and reports nothing.

## 7. Retention and purge

Retention needs no step of its own: `retain_item` in the write transaction (§5 step 7) is the whole mechanism, and `load_items` never returns a retained row, so the next sync neither re-uploads nor deletes it. A move is the exception the same step handles: the source row is purged at once, the target holding the item.

**Purge**, an owner write:

1. `BEGIN`.
2. `purge_item` for one item by `(collection, seq)`, or `purge_retained_before` with an RFC 3339 cutoff the owner computed from its own policy. Both refuse a live row and return each removed row's `object_hash` and `conflict_object`.
3. `release_pins` with a JSON array of those hashes.
4. `COMMIT`. The purge trigger counts the rows in `store_meta.purges` for the feed's consumers.
5. Run the collector (§6) when convenient; that is where the bytes go.

`retained_bytes` reports what a purge could release before choosing a cutoff. `list_retained_page` and `count_retained` are the trash view.

## 8. Collection configuration

- **Kind and account** are declared out of band, never inferred from a sync: `set_collection_kind(collection, account, kind)` at configuration time, `load_kind` and `load_account` to read them. `ensure_collection` may run before or after and overwrites neither.
- **Policy**: `set_conflict` sets the collection's cross-source policy, `manual`, `prefer-incoming` or `prefer-existing`.
- **Rename**: `rename_collection(collection, new_id)` only. Every foreign key cascades in that one statement. Deleting and recreating the row cascades the delete instead and loses every staged edit. An account rename is one `rename_collection` per collection plus `set_collection_account`, in one transaction.
- **Generation**: `bump_generation` in the same transaction as a rekey (§11) and nowhere else; `load_generation` for a frontend that advertises an epoch (an IMAP `UIDVALIDITY`).

## 9. The projection

An engine reads a collection as one source, at the scope the verb needs (SYNC §10): `load_items` and `load_bindings` for `All`, `load_items_by_link` and `load_bindings_by_link` for `Links`, `link_for_handle` then the same two for `Handles`; always `load_conflict`, `load_probes`, `load_checkpoint`. A sync or a rekey asks for `All`, an upgrade for the handles it raises, a mutation for the placement it edits or every holder of the link id an `Add` must not collide with. Returning more than asked is allowed, less is not. Placements are derived, never stored. For a collection and a source, emit:

- one placement per item the source binds;
- one `Created` placement per item the source does not bind and the store holds a body for;
- on every `Created` placement, bound or not, an origin when the same source binds the same link id in another collection with a base present and, when the placement has a body, that body as its base;
- one `Probed` placement per probe row of the source;
- nothing for a retained item;
- under a `Links` scope, nothing for an item the source lacks: the offer is for the merge, and a verb reading by key asks who holds it.

The status is the first row that matches:

| Status | Condition |
| --- | --- |
| `Conflict` | the binding is conflicted; carries its revision and diverging body; never downgraded |
| `Tombstone` | the item is deleted and the source binds it; content kept |
| `Created` | the binding has no base (`base_present` 0 and every base column `NULL`), or the source lacks the item and a body is present |
| `Dirty` | flags differ from the base flags, both known, or the body differs from the base body |
| `Clean` | otherwise |

The level is `Full` only when a body is present, whatever the row claims. A `NULL` flag set holds no opinion in the merge.

## 10. A sync run

1. Open (§2) and project (§9). Read the checkpoint.
2. **Enumerate** the source from the checkpoint. Sort the snapshot by handle and keep a duplicate's first entry.
3. **Choose candidates.** Full snapshot: every projected placement and every listed member. Delta: the changed and vanished handles, plus every projected placement that is not `Clean`. A `Created` placement is a candidate with no remote side.
4. **Walk both sides in handle order.** Per candidate:
   - flags: merge element-wise over local, base and remote; derive `SetFlags` when the merge differs from the remote; the flag axis withholds its push when the content axis already derived one for the handle, and still writes the merge;
   - content, mutable kinds only: local body not in the base is an `Update` gated on the base revision; remote revision not in the base is a pull, which drops the local body and lowers the level; both is a conflict, settled by the source's policy: `Manual` marks the binding conflicted and records the observed revision, `PreferRemote` pulls, `PreferLocal` pushes gated on the observed revision, `KeepBoth` pulls and stages the local body as a new `Created` item under the provisional handle `<handle>`, `<hash>`, `<revision>` joined by `U+0001` and the key `dup:<hint>#<that handle>`; a `Conflict` placement seeing a newer revision re-records it and clears its diverging body for the next upgrade to refetch;
   - deletes: a `Tombstone` derives `Remove`; a member missing from a complete snapshot, or listed vanished, is a `Deleted` drop; a remote edit over a local tombstone revives and pulls, and a revision the tombstone's base does not name is such an edit, so a move whose push record was lost is abandoned with the member live in the source;
   - creates: a `Created` derives `Add`, by server-side copy from its origin when it has one;
   - rights: with `push` off nothing is pushed and everything is pulled; a forbidden kind keeps its change pending; a refused delete follows the delete policy, `Revert` (default) or `Keep`, and a source bound beside others is given `Keep`.
5. **Push in bounded chunks.** Every change carries an idempotency key derived from the collection, the handle, the kind and the state it makes true. After each chunk, write (§5) the outcomes: `Accepted` rebases the placement and, for an `Add`, supersedes the provisional handle in the same batch; `Rejected` or unreported leaves it pending.
6. **Write the checkpoint** in the batch after the last chunk, never earlier.
7. **Report events** per item, in order: `Added`, `FlagsChanged`, `ContentChanged` and `Vanished` for what was pulled, `Conflicted`, and `Created` for an accepted add; an accepted flag, body or delete push reports nothing.

A move is two halves derived by two collections' syncs in either order: `Add` by copy in the target, `Remove` with a destination in the source. Neither half is dropped for the other.

## 11. Upgrade, mutate, rekey

**Upgrade** to a tier, for the placements a consumer names:

1. Select what is below the tier, plus every placement whose level claims a tier the row does not hold (`Full` with no body, `Meta` with no summary), plus a conflicted placement holding no diverging body.
2. For an immutable kind at `Full`, ask `lookup_objects` with the placements' stated keys and adopt a body the store holds, as the base too. A mutable, conflicted or derived-key placement is fetched, never linked.
3. Fetch the rest by handle; results are keyed by handle and carry the hint, the summary inputs, and at `Full` the body and its revision. A body may be streamed straight to its blob path and referenced by a byteless `StoreObject`.
4. Assign the key once, at the first fetch carrying a hint: the hint when free in the collection, `dup:<hint>#<handle>` when this source binds the hint under another handle, minted again over a key already held. Decide from the handles, not reply order.
5. Write: item and binding inserted for a named probe and the probe dropped, summary and addresses under Annex A, the level the payload supports and never lower than held, the sort key adopted and the link id not. A conflict's fetched body lands in the binding's `conflict_object`.

**Mutate** stages an edit through the write of §5 and no direct row edit. The queue's kinds map onto it: `set-flags` to `SetFlags`, `remove` to `Remove`, `move` and `copy` to `Move` and `Copy`, `update` to `Edit`, `add` to `Add`.

| Verb | Effect |
| --- | --- |
| `SetFlags` | replace the flags; status `Dirty` unless `Created`, `Conflict` or `Tombstone` |
| `Remove` | status `Tombstone`; binding and base kept |
| `Edit` | new body stored and pointed at, base kept; nothing when the base holds it; resolves a conflict by adopting its revision and body into the base; revives a tombstone |
| `Copy`, `Move` | a `Created` placement in the target under a provisional handle with the source's origin; `Move` tombstones the source; a live holder of the identity in the target mints the key |
| `Add` | a new item at `Full` under a provisional handle, no base; fails on a live holder, revives a retained one, ignores a tombstone |

**Rekey**, when a source renumbered every handle:

1. Enumerate the new handle space and fetch enough to identify every member.
2. Match each member to its old placement by link id. A member resolving to an identity already handed out takes the minted key an old copy carried, else a mint over its own handle; pending creates count as taken.
3. In one batch: a `Rekeyed` drop of each old handle, an upsert of the same item under its new handle carrying body, summary, level, flags, base and pending state, the sort key preferring the fetch's; a `Deleted` drop of each handle the new space lacks.
4. The store bumps the generation in the transaction applying that batch, recognising the rebuild by its `Rekeyed` drops (§5 step 8); the engine emits no op for it.

## 12. Absorbing a write across sources

When a batch from one source folds into an item other sources bind:

1. Adopt a known flag set, sort key and summary over the shared one; leave the shared value alone for an unknown one. A tombstone adopts no content. Merge the level as a maximum, under the rule that `Full` needs a body.
2. Compare bodies from the binding's `shared_object`, falling back to `base_object` until the source has folded once. The incoming body differs from the source's base while the shared body differs from what the source last agreed with: a divergence, settled by the collection's policy, `manual` flagging the item and recording the diverging body in `items.conflict_object`, `prefer-incoming` adopting, `prefer-existing` keeping. Only the source having changed is a fast-forward. Flags never diverge.
3. Move `shared_object` to whatever the item settled on. Clear the binding's own conflict on an upsert carrying no divergence, releasing the pin its diverging body held.
4. A `Deleted` drop or a `Tombstone` upsert marks the item deleted; the dropping source loses its binding, a tombstoning one keeps it; a live upsert clears it. With no binding left, `retain_item`, then `purge_item` when the account holds the identity live elsewhere. A `Superseded` or `Rekeyed` drop marks nothing.

Every other source then projects the change as its own `Dirty` or `Tombstone` and pushes it on its next run. A source lacking the item is offered a `Created` only when the body is held.

## 13. The queue

**Enqueue**, as a producer, under a shared lock on objects.lock held across the whole procedure:

1. Write the body the action needs, if any (§4).
2. `BEGIN`; `ensure_collection`; at most one `store_object`; `enqueue_action` with the kind, the versioned JSON payload and the body's hash in `object_hash`, which pins it; `COMMIT`. The statement stamps `created_at`.
3. Release the lock. Do not assume when the owner will run.

**Drain**, as the owner:

1. `list_queued_collections`, then per collection `load_pending_actions` outside any transaction.
2. Per row in ascending id: `BEGIN`; `claim_action` first, and end the transaction touching nothing when it deleted no row, since another owner applied it; apply the action as the corresponding mutation of §11 (`add` derives the summary and addresses from the body, a duplicate link id parks unless the holder is retained, which revives it); settle refcounts, the row's pin included; `COMMIT`. No network inside.
3. A failure: `bump_attempts`, row left pending. A permanent failure: `park_action` with the error, later rows proceeding. An unrecognised kind, or one this owner lacks the capability for: skip, touching nothing, attempts unbumped, later rows proceeding.

**Cancel or acknowledge**, as the owner: `cancel_action` in one transaction with the refcount settle. An intent whose effect is not a store mutation is at least once; the performer deduplicates.

Operators read `load_parked_actions` store-wide; a reader overlays `load_pending_actions` for read-your-writes.

## 14. A reader

- **Collections**: `list_collections`, `list_collections_by_account` (`NULL` for a single-account store), `list_accounts`.
- **A listing** in natural order: `list_mail_page_desc`, `list_contacts_page_asc`, `list_events_page_asc`, `list_tasks_page_asc`, `list_journals_page_asc`, cursor `(sort_key, seq)`, the first page with no cursor. A mixed calendar reads three pages and merges on `(sort_key, seq)`; `component_of` says which table holds an item. `list_items_page_asc` and `list_items_page_desc` give the kind-agnostic row.
- **One item**: `get_mail`, `get_contact`, `get_event`, `get_task`, `get_journal`, or `get_item`. Render from the summary; a `NULL` body, or a blob file gone under a purge, is not hydrated and not an error.
- **A sweep** that must see every row once: `list_items_page`, cursor on link id.
- **People**: `list_address_placements(address, role)`, `role` `NULL` for any; `list_domain_placements` for a domain, by scan.
- **Identity across collections**: `list_link_placements(link_id)`, `list_object_placements(hash)`, `seq_by_link`.
- **Trash**: `list_retained_page` (cursor on `seq`, `0` first), `count_retained`, `retained_bytes`.
- **Change**: `PRAGMA data_version` to know that something committed; `load_change_cursor` then `list_items_changed_since` and `list_collections_changed_since` to know what, reconciling keys only when `purges` moved.
- **Sync state**: `list_sources`, `list_conflicted_bindings(account)`, `count_probes`, `load_kind`.

Never present a deleted row as live outside the trash view.

## 15. The indexer and the query client

**Refresh**, as the indexer, holding an exclusive advisory lock on index.lock and no store lock:

1. Open index.db read-write and attach pimdir.db read-only as `store`. `load_index_meta`; on a version or tokenizer mismatch, delete index.db, apply migrations/search/0001_init.sql, `init_index_meta`.
2. `load_change_cursor` from the store before the pass.
3. `load_changed_items` above `store_change`, in stamp order, in bounded batches, one index transaction each. Per row: `object_indexed`, else extract the body under SEARCH §6 and `insert_object` plus `insert_object_text`; `upsert_placement`; `insert_summary_text` for a bodiless row and `delete_summary_text` once it has a body; `replace_flags` then `insert_flag`; `replace_occurrences` then `insert_occurrence` within the horizon when the body changed; `upsert_message` and `upsert_thread` for mail, re-keying a thread on join by its lowest `(sort_key, link_id)` member. A deleted or retained row: `delete_placement`, which takes its flags, occurrences and summary text.
4. When `purges` or a collection stamp moved: `placements_gone` and `objects_gone`, then `delete_placement` for each placement, and `delete_object` (the FTS row, by rowid) then `delete_object_row` for each body.
5. When the horizon rolls: `set_horizon`, then `items_to_reexpand` and re-expand those alone.
6. `set_index_cursor` in the transaction that completes the pass.

**Query**, as a client, on index.db read-only with the store attached: compile the query under SEARCH §8, structured terms to seeks (`list_address_placements` on the store for an address, a range on the sort key, `flagged`, `occurring_between`, `thread_members`), text terms to `match_objects` and `match_summaries`, intersect, order by the store's sort key, present each hit through `hit` and report `coverage` beside the result. Tagging goes through the queue as a producer (§13), never through the index.

## 16. Running the vectors

- **vectors/objects.json**: for each case, name the body under both algorithms and compare name and shard path. Every store implementation, before anything else.
- **vectors/summaries.json** with vectors/fixtures/: read each fixture as bytes (they are CRLF, and a text-mode read changes the object name), check its stated hashes first, derive the link id, summary row, address rows and sort key, compare as parsed structures. A case with a `hint` and a `handle` checks the minted key. Per kind written.
- **vectors/sync/**: build the `store` rows, run the `run` verb against the `remote` answers, compare the pushes in order, feed back the `outcomes`, compare the `events` and the rows after, `changed` stamps and `retained_at` instants excluded, chunks concatenated. Every engine.
- **vectors/search/**: build the fixture store from store.json, index it at each case's `now`, run the query with its sort, compare hits as `(account, seq)`, ordered where the sort says so, and the coverage. Every index.

checks/vectors.py validates the files' shape and references without an implementation; only an implementation runs a case. Vendor the files if the build cannot read them in place, record their digests, and re-check them against this repository in CI.
