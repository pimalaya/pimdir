# Pimdir implementation guide

Status: informative

The procedures an implementation runs, in the order it runs them, naming the statements under queries/ and the vectors under vectors/ at each step.

This document restates the rules of [STORAGE.md](./STORAGE.md), [SYNC.md](./SYNC.md) and [SEARCH.md](./SEARCH.md) as steps and tables. It adds none; where it and a part disagree, the part wins. §n of a part is written STORAGE §n, SYNC §n, SEARCH §n.

§9 to §12 run the engine, §15 the index; what either owes the store is in §5.

A reader new to the model starts with [OVERVIEW.md](./OVERVIEW.md).

## Contents

1. [Conformance checklist](#1-conformance-checklist)
2. [Opening a store](#2-opening-a-store)
3. [The migration runner](#3-the-migration-runner)
4. [Naming, writing and reading a body](#4-naming-writing-and-reading-a-body)
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

STORAGE §17, SYNC §12 and SEARCH §12 name the profiles, what each owes and how an implementation states the ones it meets; the steps below build them in order. Most implementations are readers or producers. The owner, the engine and the index are large; the reference implementation is there to be used for them.

A **reader** opens the store and lists it:

| Step | What | Where |
| --- | --- | --- |
| 1 | SQLite 3.37 or later for the canonical statements, 3.18 for text of your own; `PRAGMA foreign_keys = ON`, `PRAGMA synchronous = FULL` and a busy timeout, a read-only open, no lock; refuse a store another draft wrote; a store you did not create opened with `PRAGMA trusted_schema = OFF` and the defensive flag where your SQLite has them, its triggers and views checked against the canonical text where it lacks the pragma | STORAGE §4.1, §4.2, §8, §18 |
| 2 | Decode the columns as §13 says | STORAGE §13 |
| 3 | Serve the reads from queries/storage/read/, live rows only, level-aware, snapshot-consistent; a body once its bytes hash to its name, a range once the whole file has, as §4 reads one | STORAGE §7, §14.1 |
| 4 | Follow the change feed for anything derived from the store | STORAGE §4.5 |

A **producer** is a reader that appends actions:

| Step | What | Where |
| --- | --- | --- |
| 5 | Name a body by BLAKE3, check every name before building a path, and write it as §4 says, never replacing a file and keeping a name held only once it checks, under the staging lock; pass vectors/objects.json | STORAGE §5, §8, §16 |
| 6 | Check the sources' capabilities first, recommended so a gap shows at the action, and refuse what a declared source does not support (the owner parks it otherwise); name an intent's performer; then enqueue in one transaction with queries/storage/queue/, the body pinned, an action and its versioned payload as STORAGE §15.3 says, valid against its schema under payloads/ (vectors/payloads.json), every `X-PIMDIR-` property removed from a resource the user did not write, `PRAGMA secure_delete = ON` on the connection | STORAGE §15.1, §15.3, §15.6, §18, Annex B |

An **owner** is the one process that mutates the store:

| Step | What | Where |
| --- | --- | --- |
| 7 | Create the store's directories `0700` and its files `0600`; `PRAGMA secure_delete = ON` on every writing connection, WAL with a journal size limit on a local store; apply migrations/storage/ through the runner of §3 | STORAGE §4.1, §6, §18 |
| 8 | Take the owner lock before any write; fail at once when it is held | STORAGE §8 |
| 9 | Run the write transaction of §5 for every batch, with queries/storage/owner/ | STORAGE §14 |
| 10 | Derive summaries, addresses and sort keys under Annex A for each kind written, a message's header read by A.1's parses and a zoned time resolved by A.3's; pass vectors/summaries.json for that kind | STORAGE Annex A, §16 |
| 11 | Retain rather than delete, purge a moved or requested row only, collect only under both locks and never between chunks, unlinking only well-formed names; quarantine a body failing its name, read or met under a name a write finds held, never unlink it; erase on request as §7 says | STORAGE §5, §7, §11 |
| 12 | Declare every source's capabilities before draining for it; drain the queue store-wide with claim-first, roll back before parking, park or skip as §13 says | STORAGE §15, §15.6 |
| 13 | Back up through the backup API or `VACUUM INTO`, then objects/ and quarantine/, under the staging lock; after a restore, `raise_incarnation` before anything opens the store; never a file-synchronisation tool | STORAGE §8 |

An **engine** (SYNC §12) is an owner that reproduces every case under vectors/sync/, over **connectors** answering SYNC §4's requests. An **indexer** (SEARCH §12) adds, for the canonical shape, SQLite 3.43 with FTS5, migrations/search/ and the indexer's statements of SEARCH §3, or a shape of its own, named in its `index_meta`, answering the same hit sets, and every **query client** on it, refusing an index it does not implement, answers the cases under vectors/search/ alike.

Use the statements verbatim. Each prepares against the canonical schema (checks/schema.sh proves it on every push), and checks/invariants.sh runs them through the scenarios the parts argue from. Text of your own, which an SQLite older than 3.37 needs, is yours to keep equivalent: every name, parameter, result column and effect, STORAGE §7's invariants and the model vectors. One name may run several statements of yours, in order in one transaction, nothing else writing between them; say you run text of your own when you state your conformance, `storage-draft-08 owner (own statement text)` (STORAGE §4.4, §17).

## 2. Opening a store

**As the owner:**

1. Open owner.lock beside pimdir.db, never through a symbolic link (`O_NOFOLLOW`) and created `0600` in a store directory created `0700` (STORAGE §18), and take an exclusive whole-file lock on the open file without waiting: `flock(fd, LOCK_EX | LOCK_NB)` on Unix, `LockFileEx` with `LOCKFILE_EXCLUSIVE_LOCK | LOCKFILE_FAIL_IMMEDIATELY` over the whole range on Windows, never an `fcntl` or `lockf` record lock. If it is held, fail now, naming the store. Every other lock below (objects.lock, index.lock) is taken with the same call, `LOCK_SH` where it is shared.
2. Open pimdir.db, `0600` when you create it. Set `PRAGMA foreign_keys = ON`, `PRAGMA synchronous = FULL` and `PRAGMA secure_delete = ON`, run `create_param` (every list parameter's table, STORAGE §4.4) and, on a local filesystem, `PRAGMA journal_mode = WAL` with a `PRAGMA journal_size_limit` of your choosing. On a network filesystem use rollback journal or `PRAGMA locking_mode = EXCLUSIVE`, never WAL or `mmap`.
3. Run the migration runner (§3), which refuses a store another draft wrote. On a fresh database it also runs `init_store_meta`, which records `blake3` as the store's algorithm.
4. Read `load_store_meta`. Refuse the store when `format` is not `pimdir`, `version` disagrees with `PRAGMA user_version`, or `hash_algo` is not `blake3`: an algorithm you do not know is a store you refuse, never one whose bodies all fail their names. As an engine, refuse it too when `sync_version` names another SYNC draft than yours: its sync state means what that draft says. `NULL` is a store no engine has written yet.
5. Keep the lock open until the process gives up the store. Several connections in one process share the one lock; release and retake it as one operation, never in between.

**As a reader:** open pimdir.db read-only (`?mode=ro` in a URI), set `PRAGMA foreign_keys = ON`, `PRAGMA synchronous = FULL` and a busy timeout, run `create_param` (a temporary table, so a read-only open takes it), take no lock.

- Run `load_store_meta` first. When it fails, the store lacks `format_version`: a draft before storage-draft-08 wrote it, so refuse it. Text of your own judging the store may read `store_meta` with `*` and take the columns it knows by name, the one read of `*` STORAGE §4.4 allows. When its `format_version` is not your draft's name, refuse it, naming both, and likewise when its `hash_algo` is not `blake3`. Once STORAGE is released, refuse instead a store whose `read_version` is above your version, and read one below your version as that version defines it.
- Never write, convert or delete a store you refuse.
- Open a store you did not create (a copy received, someone else's backup) with `PRAGMA trusted_schema = OFF` and `SQLITE_DBCONFIG_DEFENSIVE` set, each where your SQLite has it (3.31 and 3.26); below 3.31, read `sqlite_master` first and refuse a store holding a trigger or a view whose text 0001_init.sql does not create, and register no function with a side effect on that connection; and refuse or confirm with the user one whose directory or pimdir.db another user can read or write (STORAGE §18).
- Detect change with `PRAGMA data_version` or the feed (§14), recording the store's `store_id` and `incarnation` with your cursor.

**As a producer:** open read-write, take no owner lock, refuse a store as a reader does (once released, also one whose `produce_version` is above your version), set a busy timeout and `PRAGMA secure_delete = ON`, and perform nothing but the enqueue of §13 under a shared lock on objects.lock. Record the store's `store_id` and `incarnation` with every queue id you follow.

## 3. The migration runner

1. Read `PRAGMA user_version`; `0` is a fresh database: go to step 3.
2. Read `load_store_meta`. Refuse the store, naming both versions, and write nothing when the statement fails (no `format_version`, an earlier draft's store) or when `format_version` is not your draft's name; once STORAGE is released, when `version` is above the highest NNNN you ship. Refuse it too when `hash_algo` is not `blake3`. Never reconcile, migrate, rebuild nor delete it. A reader and a producer refuse the same way and stop here.
3. List migrations/storage/NNNN_*.sql ascending. For every NNNN above the current version: `BEGIN`, execute the script, `PRAGMA user_version = NNNN`, `set_store_version` with NNNN and the `read_version` and `produce_version` the migration states, `COMMIT`. On a fresh database, 0001_init.sql sets `PRAGMA auto_vacuum = INCREMENTAL` before its first table, and `init_store_meta` with version 1 and your Annex A revision runs inside its transaction, drawing the store id. A failure rolls back and stops. A migration keeps every row of every table.
4. Read `derivation` from `load_store_meta`. Below your Annex A revision, re-derive from the held bodies the columns the revisions between changed, paging them with `list_held_mail` and `list_held_tasks`, and `set_derivation` with yours in the transaction of the last page; an interrupted pass runs again on the next open. Above yours, `set_derivation` with yours in the transaction of your first write of a summary, an address or a sort key, so the next owner at a later revision re-derives what you wrote.

A store and its program move together while STORAGE is a draft: a program of another draft finds the store refused, and a program built on a draft is reinstalled over a new store once STORAGE is released.

The index has no migrations: an index.db of your shape at an earlier version, with another tokenizer, or built from another store or incarnation is deleted and rebuilt, and one of another shape or a later version is refused and left alone (§15).

## 4. Naming, writing and reading a body

**Name:**

1. Digest the raw bytes, whole, with BLAKE3 at its default 32 bytes, the one algorithm (`store_meta.hash_algo` is `blake3`).
2. Encode in RFC 4648 §6 base32 (`a` to `z`, `2` to `7`), lowercase, no padding: 52 characters.
3. The path is objects/, the first two characters, then the whole name: objects/v4/v4jutopv… for the empty body.

Check the encoder against the `base32.cases` in vectors/objects.json before trusting anything else, then the digests and paths against its cases, the empty body included.

A name you did not just compute (from a row, a payload, a directory listing, a remote) is 52 characters of `a` to `z` and `2` to `7`, or it is no name: build no path from it. Open the shard directory, then the blob, without following a link: `openat` with `O_DIRECTORY | O_NOFOLLOW`, then `O_NOFOLLOW`, or `lstat` first where those are missing.

**Write:**

1. Create the shard directory if needed.
2. Write to a period-prefixed temporary file in that directory, named uniquely to this writer (a process id and a counter), `fsync` it (`fcntl` with `F_FULLFSYNC` on macOS).
3. Move it onto the final name without replacing a file there: `link` then `unlink` of the temporary, `renameat2` with `RENAME_NOREPLACE` on Linux, `renamex_np` with `RENAME_EXCL` on macOS, `MoveFileExW` without `MOVEFILE_REPLACE_EXISTING` on Windows. On Android, whose SELinux policy denies an app `link` on its own files, `renameat2` with `RENAME_NOREPLACE` from API 30. Never a plain `rename`, which replaces.
   - Where none of these is offered or allowed (Android before API 30, whose system call filter may end the app on a raw `renameat2`, or a kernel answering `ENOSYS` or `EINVAL`), create the final name with `O_CREAT | O_EXCL`, copy the temporary's bytes into it, `fsync` it, then unlink the temporary. Until the copy is synced the name holds part of the body, and a crash leaves that part there; a copy that fails unlinks the part it created, the temporary still holding the bytes.
4. When the move fails because the name exists, or you would skip the write because the name or its row is there, read the file under the name whole and check it against the name before keeping it.
   - It passes: delete the temporary and keep it.
   - It fails, a part a crashed copy left or any other bytes: as the owner, take objects.lock exclusively, serialised against your own writers, check it again, move it to quarantine/ as a read's mismatch is moved (below), and move your temporary again; as a producer, move nothing, delete the temporary, report the name and enqueue nothing, the bytes staying with your caller until the owner frees the name.
   - Any other failure of the move (on Windows, a name a deleted file still holds open) fails the write; try again later.
5. `fsync` the shard directory; Windows has no such flush.

A body may be written before the transaction that references it opens, and a body of any size should be: the writer's locks, not the file's age, keep the collector away from it.

**Read:**

1. Read the whole file through one descriptor, hashing as you go, and compare the digest with the name before you show, parse, index, push, copy or send the body. Streaming it somewhere, fail the stream at its end on a mismatch, before anything built from it is committed: abort the upload or the submission.
2. For part of a body, an attachment or a message's head, read the whole file through the same descriptor first and check it; every range through that descriptor is then checked. Record nothing: the next open checks again. On Windows, open with `FILE_SHARE_DELETE`, so the collector can still unlink the file.
3. On a mismatch the body is missing, as if its file were gone. A reader or a producer reports it and moves nothing. The owner takes objects.lock exclusively, serialised against its own writers, checks the file again, moves it to quarantine/ under its name, a period and a suffix unique to the move, and reports it; the row stays, and the next `Full` upgrade fetches the body again where a source holds it. Never unlink it.

## 5. The write transaction

One batch of `UpsertPlacement`, `DropPlacement { handle, reason }` (`Deleted`, `Superseded` or `Rekeyed`), `StoreObject { hash, size, bytes? }`, `SetCheckpoint`, `SetCoverage` and a round's `OpenRound`, `Stamp`, `SetRoundCursor` and `CloseRound`, applied in order and never reordered: the store's own interface (STORAGE §14), which an engine calls (SYNC §10) and any owner may. An operation cut into several batches writes them as chunks, between which nothing collects.

A statement ending in `RETURNING` (`add_reference`, `remove_reference`, `collect_before`, `release_before`, `purge_item`, `delete_unbound_item` and others) answers rows. Run it through the driver's query call and step its cursor to the end, never through an execute call that discards the rows, and on Android not through `SQLiteDatabase.execSQL`.

1. For every `StoreObject` carrying bytes, write the body (§4). One carrying none is already at its path.
2. `BEGIN`.
3. `store_object` for every `StoreObject` (the refcount starts at zero and is settled in step 11).
4. `ensure_collection` for the collection, which inserts an undeclared row and never overwrites a declared one. Read the policy with `load_conflict`. An engine writing its first batch to a store whose `load_store_meta` answers no `sync_version` runs `set_sync_version` with its own here; one naming another draft of SYNC refuses the store before any verb (SYNC §10).
5. Resolve the batch's keys:
   - Each `DropPlacement` names a handle: `link_for_handle` gives its link id; a handle nothing binds drops nothing.
   - Each `UpsertPlacement` carries a link id, and its handle is resolved the same way, so a handle bound to another link id is in the batch's diff. One carrying none for a handle nothing binds is refused: nothing enters the store unnamed.
   - A mail upsert naming by its bare hint a row it does not agree with (`load_mail_summaries_by_link` disagreeing on subject, date or sender, or a retained row on size where both state one), whatever that row is (a pending create of this source, a live item others or none bind, a tombstone, a retained row), is keyed `dup:<hint>#<handle>` instead, minted again over a held key, whichever step named it (STORAGE §9's table, §14). A page before the last, a head and an upgrade load this source's holders alone, so the write enforces the rule.
6. Read what the batch touches and nothing else: `load_items_by_link`, `load_bindings_by_link`, the kind's `load_<kind>_summaries_by_link`, `load_addresses_by_link`, and for mail and tasks `load_in_reply_to_by_link` and `load_categories_by_link`, the batch's link ids in the `links` slot (`clear_param`, then `bind_param` per id), so step 7 writes a summary, an address set or a list only when it moved. Each seeks the ids, so a page costs the same in a mailbox of any size. A merge over the whole collection reads `load_items`, `load_bindings`, `load_<kind>_summaries`, `load_addresses_by_collection`, `load_in_reply_to` and `load_categories` instead, binding no slot.
7. Merge each placement into its shared item and binding under SYNC §9 and STORAGE §14, then persist the diff:
   - a new item: `seq_for_link_any` with the collection and a stated hint, which answers the `seq` of that link id in a collection of the same kind only, `bump_next_seq` when it returns nothing or the key is derived (`alt:`, `hash:`, `dup:`), then `insert_item`; its flags then follow, `retain_flags` and `add_flags` with the set in the `flags` slot, an unknown set leaving the slot empty and `flags_known` 0; a retained row under the same key (`retained_item`), agreeing, is revived instead, `revive_item`, releasing only the pins the revive replaced: a placement carrying no body keeps the retained body for an immutable kind, as its base too, while a mutable kind revives holding none, at `Meta`, its retained body kept as a retained item minted over the binding's handle as §12 step 3 keeps a policy's loser and reported `Overruled`; a tombstone still propagating is revived the same way;
   - a new binding: `insert_binding`, then `retain_base_flags` and `add_base_flags` for its base set; a binding whose handle differs from the incoming one is a refused write unless a `Superseded` or `Rekeyed` drop for the old handle precedes it in the same batch; a handle `link_for_handle` resolves to another link id is retired first, `delete_binding` and the retention of step 7's last bullet when it was the item's last (STORAGE §10);
   - a moved item or binding: `update_item`, `update_binding`, which carries no handle, each followed by its set as above, a set written again as it was moving no row and drawing no stamp;
   - a named placement's summary and addresses, derived under Annex A: `upsert_<kind>_summary`, `replace_addresses` then one `insert_address` per row, for mail `replace_in_reply_to` then one `insert_in_reply_to` per id, for a task `replace_categories` then one `insert_category` per value, and `stamp_item` when only those rows moved;
   - a `Deleted` drop of a binding: `delete_binding`; of the item's last binding: `delete_item_bindings` and `retain_item`, which stamps `retained_at` and keeps the body pinned; then, when `held_elsewhere`, bound to the retiring row's `object_hash`, finds the link id live in another collection of the account with that body, `purge_item` on `retained_item`'s seq and `release_pins`.
8. A `Rekeyed` drop anywhere in the batch makes it a rebuild: `bump_generation` for the collection, once, in this transaction.
9. `SetCheckpoint`: `upsert_checkpoint` for this source, last in the batch, with `set_coverage` for a `SetCoverage`. A round's ops, in batch order: `OpenRound`, `open_round` before the first page's upserts; `Stamp`, `stamp_bindings` with the page's handles after them; `SetRoundCursor`, `set_round_cursor`; `CloseRound`, `close_round`, last in the write after the last chunk.
10. Never reorder the batch: a provisional handle superseded by an accepted one is two entries for one handle in one order, and a rebuild's drops all precede its upserts.
11. Settle refcounts: `adjust_refcount` per hash by the batch's net change, or `recompute_refcounts` for the whole store. A batch that stored or dropped no object skips this.
12. `COMMIT`. Reclaim nothing: an object at refcount zero stays for the collector.
13. When you keep an index, refresh it (§15) once the batch is committed, so the filters a list asks of the index trail the rows it reads from the store by one batch at most.

The stamps of the change feed are written by the schema's triggers; a writer never binds one, and `stamp_item` only asks for one.

## 6. The collector

1. Hold the owner lock (§2) and take an exclusive lock on objects.lock. The first excludes other owners, the second excludes producers between a body and its enqueue.
2. Serialise against the process's own writers, and against a verb between two of its chunks: the owner lock does not exclude a second connection in the same process, and a body streamed in one chunk has no pointer until the next.
3. `BEGIN`; `recompute_refcounts`; `list_garbage_objects` (refcount at or below zero), `delete_garbage_objects`; `COMMIT`.
4. Walk objects/ by `lstat`, following no link. Unlink a regular file when its name is 52 characters of `a` to `z` and `2` to `7` beginning with the two that name its shard directory, itself a directory so named, and `object_exists` answers nothing for it. Leave everything else in place and report it: a period-prefixed file belongs to a writer mid-move, and a link or any other name to nobody you know. Never walk quarantine/. An unlink that fails, on Windows a file a reader holds open, is made by the next run.
5. `PRAGMA incremental_vacuum` when you want the pages the run freed back on the filesystem, as after a purge or a release.
6. Report rows dropped, files unlinked, bytes freed, and what you left.

Run it on a schedule of the owner's, and after a purge. A store that never collects grows without bound.

## 7. Retention and purge

Retention needs no step of its own: `retain_item` in the write transaction (§5 step 7) is the whole mechanism. `load_items` never returns a retained row, so the next sync neither re-uploads nor deletes it. A move is the exception the same step handles: the source row is purged at once, the target holding the item.

**Purge**, an owner write:

1. `BEGIN`.
2. `purge_item` for one item by `(collection, seq)`, or `purge_retained_before` with an RFC 3339 cutoff the owner computed from its own policy. Both refuse a live row and return each removed row's `object_hash` and `conflict_object`.
3. `release_pins` with those hashes in the `hashes` slot.
4. `COMMIT`. The purge trigger counts the rows in `store_meta.purges` for the feed's consumers.
5. Run the collector (§6) when convenient; that is where the bytes go.

**Collect below a date**, an owner write on the user's request, never a sync's: `BEGIN`; `collect_before(collection, before)`; `recompute_refcounts`; `COMMIT`; the collector when convenient.

`collect_before` removes the live mail older than `before` that owes nothing (a binding, so a source still holds it; no conflict, no pending create, no unpushed flag, no reference a person made) with its bindings, summary and addresses, and returns the seqs. No tombstone, no push. Drain the queue first, and never collect between two chunks. A later widening lists the collected mail again.

**Release bodies below a date**, an owner write keeping the headers, never a sync's: `BEGIN`; `release_bases_before(collections, until)`, then `release_before(collections, until)` with the same values, which returns the seqs that went back to `Meta`; `recompute_refcounts`; `COMMIT`; the collector when convenient. Never between two chunks.

- Mail that needs its body keeps it: a conflict, a pending create, a local edit, no binding, a source of the collection not binding it yet. An unpushed flag does not.
- Undated mail lies below any date, and a `NULL` `until` releases everything else too.
- The next `Full` upgrade of a released message fetches or links it again; a sync leaves it at `Meta`.

**Erase**, an owner operation on the user's request, every writing connection under `PRAGMA secure_delete = ON`:

1. Purge the item as above, once it is retained, or `delete_unbound_item` then `release_pins` for one no source binds.
2. Run the collector (§6), which unlinks its body unless another row names it.
3. Where an index is kept, refresh it (§15): `placements_gone` and `objects_gone` name what went, the thread is pruned, then `optimize_text` merges the full-text segments.
4. `PRAGMA wal_checkpoint(TRUNCATE)` on pimdir.db and on index.db, again until no frame is left behind a reader.

A backup, quarantine/ and the filesystem's free blocks and snapshots keep what they hold.

`retained_bytes` reports what a purge could release before choosing a cutoff. `list_retained_page` and `count_retained` are the trash view (§14): a `NULL` `retained_at` marks a row a source still binds and cannot remove yet, which no purge takes.

## 8. Collection configuration

- **Kind and account** are declared out of band, never inferred from a sync: `set_collection_kind(collection, account, kind)` at configuration time, `load_kind` and `load_account` to read them. `ensure_collection` may run before or after and overwrites neither.
- **Display name**: `set_collection_name(collection, account, name)` records what the collection is called, which is not what addresses it. A frontend namespacing its ids (`work/INBOX`, `caldav/<uuid>`) writes the bare name here and renders it; the id stays the key, and nothing joins on the name.
- **Role**: `set_collection_role(collection, role)` records what the source states a collection is for (`sent`, `trash`, `default`), or clears it with `NULL`. Write it on every sync from the source's own listing, next to the name, never from the name. Setting a role on one collection takes it from the one that held it; `list_collections` returns it.
- **Policy**: `set_conflict` sets the collection's cross-source policy, `manual`, `prefer-incoming` or `prefer-existing`.
- **Rename**: `rename_collection(collection, new_id)` with `rename_queue_targets(collection, new_id)` in one transaction: the first cascades every foreign key, restamps the items and counts in `purges` (a consumer reconciles its keys), the second follows the id into the `target_collection` of pending `move`, `copy` and superseding `add` rows, which the owner reads in place of the payload's. Deleting and recreating the row instead loses every staged edit. An account rename is one `rename_collection` per collection plus `set_collection_account`, in one transaction.
- **Removal**: refused while the collection holds a pending or parked action, so cancel those first (§13). Then `delete_collection(collection)` then `recompute_refcounts`, in one transaction, then the collector when convenient. Ask `collection_holds_objects` first, and skip the store-wide recount when it answers false. Nothing under it is retained.
- **Generation**: `bump_generation` in the same transaction as a rekey (§11) and nowhere else; `load_generation` for a frontend that advertises an epoch (an IMAP `UIDVALIDITY`).

## 9. The projection

An engine reads a collection as one source, at the scope the verb needs (STORAGE §14, SYNC §10):

- `All`: `load_items` and `load_bindings`;
- `Links`: `load_items_by_link` and `load_bindings_by_link`;
- `Handles`: `link_for_handle`, then the same two;
- always `load_conflict`, `load_checkpoint` with the coverage it serves, and `load_round`; a round's last page adds `list_unstamped_bindings`.

A delta, a round's last page or a rekey asks for `All`. A page before the last asks for `Handles` of its members and `Links` of their hints, an upgrade for the handles it raises, a mutation for the placement it edits or every holder of the link id an `Add` must not collide with. Returning more than asked is allowed, less is not.

Placements are derived, never stored. For a collection and a source, emit:

- one placement per item the source binds;
- one `Created` placement per live item the source does not bind and the store holds a body for;
- on every `Created` placement, bound or not, the origin `origin_for_link` gives: the same source binding the same link id in another collection with a base present and, when the placement has a body, that body as its base;
- on every `Tombstone` placement, the destination `destination_for_link` gives: the same source holding a pending create of the same link id in another collection, named by that create's handle;
- the tombstones whose remove is held, `list_superseded_pending`: an add superseded them and the item it created is still a pending create of a source syncing its collection;
- on every `Created` placement whose item superseded one of its own identity elsewhere, the binding it may be moved from, `list_superseded_bindings`: this source binding the superseded item with a base, its collection, handle and revision;
- for both, the same link id is the key itself or the key minted over the provisional handle it derives, `dup:<key>#` then `U+0001` and the key, which a `Copy` or a `Move` gives its create beside a live holder (§11); the bare key wins;
- nothing for a retained item;
- under a `Links` selection, nothing for an item the source lacks.

The status is the first row that matches:

| Status | Condition |
| --- | --- |
| `Conflict` | the binding is conflicted, or the item is (two sources disagree); carries the revision and diverging body; never downgraded |
| `Tombstone` | the item is deleted and the source binds it; content kept; a tombstone with no base derives no remove, its binding is dropped |
| `Created` | the binding has no base (`base_present` and `base_flags_known` 0, every other base column `NULL`), or the source lacks the item, the item is live and a body is present |
| `Dirty` | flags differ from the base flags, both known, or, for a mutable kind, a body is present and differs from the base body |
| `Clean` | otherwise |

The level is `Full` only when a body is present, whatever the row claims. An unknown flag set holds no opinion in the merge. A placement with no body owes no body.

## 10. A sync run

1. Open (§2) and project (§9). Read the checkpoint, the coverage it serves and the open round. A scope on anything but mail is refused.
2. **Choose the listing** (SYNC §5):
   - Resume the open round from its cursor (from its first page when it holds none, a parked round) when its scope is the one asked for and `load_round`'s `round_band` says it lists a band exactly when this run would.
   - Else open a round when no round ever closed, when one is open over another scope or of the other kind, or when the scope reaches outside the coverage. A source whose checkpoint is bound to no scope may list only the adjoining band the coverage lacks, keeping its checkpoint; `open_round` records it with `:band` 1.
   - Else run a delta from the checkpoint, recording a narrower scope with `set_coverage`.
   - A cursor the source rejects restarts the round: `open_round` again, a new id.

   Resuming, **list the head first** when the connector lists heads, and between pages if you like, never between the last page and the close:
   - a delta head from `load_round`'s `round_checkpoint`, or for a band round from the source's checkpoint;
   - else a band head from `round_started_at`, which the connector takes less two days.

   Check the head against the run's scope, not the band. Write it as a page before the last (step 4), its candidates its members and vanished handles alone, no `Add` derived.

   A delta head runs `stamp_bindings` with its handles and `set_round_cursor` with a `NULL` cursor and its checkpoint. A band head stamps nothing and records nothing; the connector lists its band again in the round's last page. A head position the source rejects restarts the round over the run's scope, never a band.
3. **Enumerate** a page. Sort it by handle and keep a duplicate's first entry. A page neither last nor carrying a cursor fails the run before its write, the round left open as the pages before it left it. Every member carries its meta (hint, summary, addresses, sort key); never filter it by date, the connector having done so with a two-day margin on any received-date narrowing, and saying so: `narrowed` on every page of a round its date filter narrowed, and on the last, where it can, `enumerated`, the collection's handles listed with no date filter.
4. **Write the page**, one transaction: `open_round` in the first page's; name each new member on §11's identity rules (a hint free, minted, or landing a pending create of this source); merge the bound ones; drop the vanished handles whatever their date; `stamp_bindings` with every handle listed; `set_round_cursor` with the page's cursor and any checkpoint it carries.

   A page before the last ends here; an interrupted round resumes from the cursor that landed.
5. **Choose candidates.**
   - A round's last page: every projected placement and the page's members. The based bindings `list_unstamped_bindings` returns (unstamped by this round, `date` in its scope, or unknown outside a band round) are absent; an out-of-scope placement no page listed is not, nor an undated one a band round did not list. A round the run opened on its last page has no stamps to read, so the engine applies the same rule to the placements it loaded.
   - A narrowed last page binds `:narrowed` 1: only a member dated before `round_started_at` is absent, and an undated or later-dated one only when the page hands `enumerated` (`:enumerated` 1, its handles in the `handles` slot) and that list lacks it. The others stay as they are, for a stated removal or an unnarrowed round. An unnarrowed page binds both 0.
   - When those absent are more than half of this source's based bindings in the round's scope and these number at least 20, or when the round named no member at all (no binding carries its id) and any is absent, park unless the run carries `accept_absences`: drop nothing, land the page as one before the last with `set_round_cursor` and a `NULL` cursor, skip `close_round`, and report the counts. The next run lists the round again from its first page.
   - Delta: the changed and vanished handles, plus every projected placement that is not `Clean`.
   - A `Created` placement is a candidate with no remote side. It derives nothing before the round's last page has landed, nor, carrying no origin, when its `date` lies outside the run's scope.
6. **Walk both sides in handle order.** Per candidate:
   - flags, merged element-wise over local, base and remote:
     - a flag is kept when both sides carry it or one side added it over the base, dropped when either side removed it from the base, the union when there is no base;
     - derive `SetFlags` when `add` or `remove` is not empty: `add` is what the merge carries and the remote set (the listed one, else the base) lacks, `remove` what that set carries and the merge lacks;
     - the flag axis withholds its push when the content axis already derived one for the handle, and still writes the merge;
   - content, mutable kinds only:
     - a local body not in the base is an `Update` gated on the base revision;
     - a remote revision not in the base is a pull, which takes the member's meta and, when the member carries it, its body as body and base, else drops the local body and lowers the level to `Meta`;
     - both is a conflict, settled by the source's policy: `Manual` marks the binding conflicted and records the observed revision; `PreferRemote` pulls, the local body it drops kept by the write as a retained item (§12); `PreferLocal`, when the member carries its body, keeps that body as a retained item and moves the base onto it and the observed revision in a write committed before the push (§12 step 3), then pushes gated on that revision, and when the member carries none marks the binding conflicted as `Manual` does, the upgrade settling it once it has read the body;
     - a `Conflict` placement seeing a newer revision re-records it and clears its diverging body for the next upgrade to refetch;
     - one projecting only the item's conflict marks the binding conflicted at any revision its base lacks, whatever the policy;
     - one whose fetched diverging body equals its own adopts the revision and clears;
   - held: a tombstone `list_superseded_pending` named derives nothing, no `Remove` and no `Update` riding ahead of one, and keeps its binding; a remote edit over it still revives it, and once the superseding create is accepted, withdrawn or gone it derives a plain `Remove` on a later run;
   - deletes:
     - a `Tombstone` derives `Remove`, with `to` set to its destination when the same source holds a pending create of the identity elsewhere (the connector relocates or rejects it, never deletes), and `link_id` left out when that create's key is minted;
     - a tombstone with no base derives nothing and its binding is dropped;
     - a member a round found absent, or listed vanished, is a `Deleted` drop, unless its placement holds a body its base does not: then it is re-staged as a pending create under a provisional handle;
     - a remote edit over a local tombstone revives and pulls, or follows the policy when the tombstone holds a local edit too. A revision the tombstone's base does not name is such an edit, so a move whose push record was lost is abandoned with the member live in the source;
   - creates: a `Created` derives `Add`, by server-side copy from its origin when it has one, naming the binding it may be moved from when it has one, which a connector able to move delivers by a `MOVE` then a write of the body, and one unable to by an upload;
   - never a `Remove` but from a tombstone the store holds, the consumer's or one an absence or a removal on another source left: no scope, interruption, restart, widening, collection, nor an absence other than a closed round's in its scope derives one; and never a collection deleted on a server because another source stopped listing it, unless the configuration enables it and the collection is empty or fully reconciled in the run;
   - rights: with `push` off nothing is pushed and everything is pulled; a forbidden kind keeps its change pending; a delete the rights forbid is held beside another source of the collection, one holding a binding or a checkpoint there, and reverted when this source is alone; a rejected push is pending like any other.
7. **Push in bounded chunks.** Every change carries the idempotency key SYNC §4 derives, which a connector forgets once the checkpoint after the chunk lands. After each chunk, write (§5) the outcomes:
   - `Accepted` rebases the placement as the flag axis left it; an `Add` assigned a handle supersedes the provisional handle in the same batch; an `Add` accepted with none stays a pending create for the next listing to land, not pushed again this run;
   - `Rejected` or unreported leaves it pending.

   Do not collect between chunks.
8. **Write the checkpoint** in the batch after the last chunk, never earlier: a delta's with `upsert_checkpoint`, a round's with `close_round`, which lands the checkpoint the round carries, the last page's or else the latest a head or a page recorded (the old one kept when it carries none) and the coverage: the round's scope, or the span of a band round and the coverage it adjoins.
9. **Report events** once the write recording them has committed, per item, in order:
   - `Added` for a member named;
   - `FlagsChanged`, `ContentChanged` and `Vanished` for what was pulled;
   - `Conflicted` for a divergence the run or its write recorded;
   - `Overruled` for a body a policy did not adopt, with the retained item's link id;
   - `Created` for an accepted add or a create a listing landed.

   An accepted flag, body or delete push reports nothing. Report a parked round with its counts.

A move is two halves derived by two collections' syncs in either order: `Add` by copy in the target, `Remove` with a destination in the source. Neither half is dropped for the other. A relocated member lands the target's pending create when the page listing it names it (§11), the create waiting for that page until then.

**Connector notes.** SYNC §4 and §5 state what a connector owes in protocol-neutral terms; what each provider needs to meet it is measured, dated and revised here, never in the part.

| Source | Page | Why |
| --- | --- | --- |
| IMAP | 500 UIDs per `UID FETCH` | `ENVELOPE`, flags, `INTERNALDATE` and a few header fields are under 1 KB a message: half a megabyte a response, short enough to resume cheaply |
| Graph message delta | 1,000 (`Prefer: odata.maxpagesize=1000`) | honoured with the summary `$select`, the first page in under 3 s |
| Gmail | 100 ids per `messages.list`, their metadata read in batches of 50 | Google advises batches of 50 at most; 100 reads paced near 40 a second commit every 2.5 s |
| JMAP | 500, capped by the server's `maxObjectsInGet` | the server states its own ceiling |
| DAV, Google Agenda, People | 64 bodies per `multiget` or batch | one body batch |

These sizes are safe on a slow network and under every provider's limits; raise one only on a measurement.

- **Meta in the listing**: IMAP from the same `FETCH` (`UID FLAGS INTERNALDATE ENVELOPE`, the header fields Annex A needs, `Content-Type` among them, no `BODYSTRUCTURE`); Graph from its `$select`; Gmail from the metadata read it already makes, `Content-Type` among its `metadataHeaders`; JMAP from `Email/get` with summary properties. DAV, Google Agenda and People fetch each page's bodies before handing it over.
- **Raw header fields**: read `Message-ID`, `Subject`, `Date` and `From` raw where the source serves them so, and parse them as STORAGE Annex A.1 says, since the hint is built from them: IMAP's `ENVELOPE` strings or `BODY.PEEK[HEADER.FIELDS (…)]`, Gmail's metadata headers, JMAP's `header:Message-ID:asRaw` and its siblings, Graph's `internetMessageHeaders`. JMAP's `subject` and `sentAt` and Graph's `subject` and `sentDateTime` are the server's own readings: shown until the body replaces them, they may key a message apart from a raw reading.
- **Recency order**: IMAP by UID descending, Graph's message delta by `receivedDateTime` descending as it answers, Gmail's list order, JMAP by `receivedAt` descending.
- **File ids**: Nextcloud's and ownCloud's `oc:id` (the file id with the instance id, unique across servers), Google Drive's file id. A plain WebDAV collection keyed by href alone states none.
- **Checkpoints**: IMAP `HIGHESTMODSEQ` at the select, Gmail's `historyId` and JMAP's state come up front. Graph gives its delta link, and Google its sync token, only on the round's last page, so neither lists a delta head before the round closes. A Graph delta link made under a `$filter` is bound to the scope; IMAP `CHANGEDSINCE`, Gmail's history and JMAP's state, filtered locally, are not.
- **Restarts**: an expired Graph skip token or Gmail page token rejects a cursor; an expired Gmail history id, a JMAP state the server can no longer calculate changes from, or a DAV sync token refused as invalid rejects a head.
- **Heads**: a delta head from IMAP QRESYNC `CHANGEDSINCE`, Gmail's history, JMAP `Email/changes` or DAV `sync-collection`; a band head by change time from Google Agenda's `updated`, by arrival from Graph's `receivedDateTime` or IMAP `SEARCH SINCE` over `INTERNALDATE`. A Gmail id list cached since the round began is read anew per page.
- **Received-date narrowing**: Graph delta's `receivedDateTime ge`, Gmail's `after:` (whose day is midnight Pacific time), JMAP's `after`, each two days below `since`; IMAP `SENTSINCE` and `SENTBEFORE` one day out. Every one is a narrowed listing: mark its pages `narrowed`, and hand `enumerated` on the last from IMAP `UID SEARCH ALL`, JMAP `Email/query` filtered by `inMailbox` alone, Graph's message ids with no `$filter`, or Gmail's `messages.list` by label alone, ids only, where the quota allows.
- **Stated removals**: IMAP `VANISHED`, Graph's `@removed`, Gmail's deletion history, JMAP's `destroyed`.
- **Moves**: Google answers a WebDAV `MOVE` of a member it binds with `404`, which delivers the create by upload.
- **Quotas**: a large Gmail mailbox paced by its quota fills a round for a quarter of an hour, which is what heads are for.

## 11. Upgrade, mutate, rekey

**Upgrade** to a tier, for the placements a consumer names:

1. Select:
   - what is below the tier;
   - every placement whose level claims a tier the row does not hold: `Full` with no body or with one whose blob is missing or fails its name, `Meta` with no summary;
   - a conflicted placement holding no diverging body;
   - for an item conflicted with no `conflict_object`, every binding of it whose base names a revision and no body.

   A listing names every member at `Meta`; this step is what the `Meta` tier remains for.
2. For an immutable kind at `Full`, ask `lookup_objects` with the placements' stated keys and adopt a body the store holds whose size the summary agrees with, as the base too.
   - State on the placement the body's size and, for mail, the mark and the invitation a row holding the body states (`held_mail_summary`), not its listing's.
   - A mutable, conflicted or derived-key placement, or one whose size disagrees, is fetched, never linked.
3. Fetch the rest by handle; results are keyed by handle and carry the hint, the summary inputs, and at `Full` the body and its revision. A body may be streamed to its blob path, through a temporary and the move of §4, and referenced by a byteless `StoreObject`.
4. Assign the key once, at the first meta carrying a hint (a page's or a fetch's), after a `Links` load of every hint it carries. The key `k` is the hint, prefixed `esc:` when it begins with `alt:`, `hash:`, `dup:`, `part:`, `file:` or `esc:`, or the kind's fallback for content stating none; for mail, the hint's fields read by STORAGE Annex A.1's parses. Then take the first row of STORAGE §9's table that matches what holds `k` in the collection, a row of `items` holding it whatever its state (`seq_by_link` answers for it):
   - nothing: `k`;
   - a pending create of this source, under `k` or under `k` minted over the provisional handle it derives (the bare key first): land it, below;
   - a binding of this source with a base under another handle: `dup:k#<handle>`;
   - a live item other sources bind, or none: `k`, joining it;
   - a tombstone other sources still bind: `k`, joining and reviving it;
   - a retained row: `k`, reviving it (§5 step 7);
   - any of these but the first holding mail that does not agree with the member, its `mail_summary` differing on subject, date or sender, or a retained row's on size where both state one: `dup:k#<handle>`, never joined, landed nor revived.

   Where a row mints, a minted key held by any row, a retained one included, is minted again over the same handle until free (`dup:dup:k#<handle>#<handle>`): minting never lands, joins nor revives what holds the key it would take.

   Landing a pending create is a `Superseded` drop of the provisional handle, the binding moved to the fetched one, the base set to the fetched flags and, for an immutable kind, the staged body; the staged flags and body kept.

   For a mutable kind the base takes the listed revision, and the body when one was carried. With none carried, mark the binding conflicted at that revision with no `conflict_object`, whatever the policy; report `Conflicted` beside `Created`; push nothing; let the upgrade fetch the body, which clears the conflict when it equals the staged one.

   Decide from the handles in byte order, not reply order. A mutable resource stating another hint than the one its handle was keyed under retires the old binding and is keyed afresh.
5. Write:
   - summary and addresses under Annex A;
   - the attachment mark of the walked parts and the body's octets as the size, replacing those read without the body, never the reverse while the body is held;
   - the level the payload supports, never lower than held;
   - the sort key adopted, the link id not.

   A fetched body over a placement with no local edit becomes `base_object`, with its revision as `base_revision`; one over a local edit is the both-changed case when the revision moved. A conflict's fetched body lands in the binding's `conflict_object`, or clears the conflict when it equals the placement's own. Otherwise the source's policy settles it now: under `PreferLocal`, content pushes allowed, keep the fetched body as a retained item keyed over the handle and reported `Overruled`, adopt it with its revision as the base and clear the conflict, so the next sync pushes the local body gated on that revision; under `PreferRemote` adopt it as the item's body and base, the local edit kept as §12 step 3 keeps one; under `Manual` leave it recorded.

   An item conflict's missing body lands in `items.conflict_object` under `manual`. Under a `prefer-` policy it settles the conflict as §12 settles a carried body: adopted or kept, the conflict cleared, the other body kept as a retained item keyed over this binding's handle and reported `Overruled`, unless the item holds no body either, which then waits, recorded as `manual` records it, for the fill that reads its own (§12).

**Mutate** stages an edit through the write of §5 and no direct row edit. The queue's kinds map onto it: `set-flags` to `SetFlags`, `remove` to `Remove`, `move` and `copy` to `Move` and `Copy`, `update` to `Edit`, `add` to `Add`.

| Verb | Effect |
| --- | --- |
| `SetFlags` | replace the flags; status `Dirty` unless `Created`, `Conflict` or `Tombstone` |
| `Remove` | status `Tombstone`; binding and base kept; on a conflicted binding the base adopts the conflict's revision and body (unknown when not fetched yet) and the conflict clears, on a conflicted item the item's clears, so the remove pushes against what the remote holds; on a pending create the binding is dropped and the item retained |
| `Edit` | new body stored and pointed at, base kept; no push staged when the base holds it; refused, staging nothing, when it carries `if_match` and the item holds another body; without `overrule`, refused, staging nothing, when it meets the item's or its binding's conflict and its `resolves` does not name each one's `conflict_object` (a person's resolution, naming the diverging bodies it was decided over), or states `resolves` and meets none; with `resolves`, resolves a binding's conflict by adopting its revision and body into the base, and settles an item's conflict through any binding, the item taking the edit's body whatever it is, `conflicted` cleared and `conflict_object` released, the editing binding's `shared_object` moved to the body, even when that binding's base already holds it; with `overrule` (stated by an engine settling by a rule of its own, never by a person), keeps the binding's then the item's diverging body it does not adopt as §12 step 3 keeps a policy's loser, keyed over the edited handle and reported `Overruled`, and is refused, staging nothing, while that body is not fetched; revives a tombstone |
| `Copy`, `Move` | a `Created` placement in the target under a provisional handle with the source's origin; `Move` tombstones the source; a live holder of the identity in the target gives the create the identity minted over the provisional handle it derives, minted again over a held key, and a tombstoned or retained one is revived under the identity, or minted beside when it holds a message that does not agree (STORAGE §9's table); refused for a placement with neither a body nor a based binding |
| `Add` | a new item at `Full` under a provisional handle, no base; fails, staging nothing, when its body cannot be read; fails on a live holder, revives a retained one or a tombstone still propagating, minting beside one holding a message that does not agree (STORAGE §9's table) |

A delete meant to land in a trash collection is a `Move` into it, so the trash shows it before any sync; `Remove` is for a delete meant to be final, as from the trash itself.

A provisional handle is `U+0001` followed by the link id (SYNC §2).

**Rekey**, when a source renumbered every handle and the connector reported it (SYNC §4):

1. List the new handle space in full, whatever the scope, every page read before anything is written; every member carries its meta, which identifies it.
2. Match each member to its old placement by link id; where one hint had several old copies, by the base naming its fetched revision first, then by body hash, then handle order.
   - A member resolving to an identity already handed out takes the minted key an old copy carried, else a mint over its own handle. Pending creates count as taken and are carried untouched.
   - A mutable member whose fetched revision is not its old base's is carried as a pull, or as a `Conflict` at that revision when it holds a local edit.
   - When more than half of the source's based bindings, and at least 20 of them, would match no member, park unless the run carries `accept_absences`: write nothing, leave the checkpoint and the generation alone, and report the counts. The old checkpoint makes the connector name the rekey again next run.
3. In one batch, never cut, every drop before every upsert:
   - a `Rekeyed` drop of each old handle a member carries;
   - a `Deleted` drop of each based binding no member resolves to by link id, its handle reused by the new space or not;
   - then an upsert of each carried item under its new handle, carrying body, summary, level, flags, base and pending state, the sort key preferring the fetch's.

   A server numbering from 1 again hands a carried member a gone member's handle; an upsert under it before that drop would fold the two.
4. The store bumps the generation in the transaction applying that batch, recognising the rebuild by its `Rekeyed` drops (§5 step 8); the engine emits no op for it. The batch lands the checkpoint and leaves the coverage alone.

## 12. Absorbing a write across sources

When a batch from one source folds into an item other sources bind:

1. Adopt a known flag set, sort key and summary over the shared one; leave the shared value alone for an unknown one. A tombstone adopts no content. Merge the level as a maximum, under the rule that `Full` needs a body; a pull without a body writes `Meta`.
2. For a mutable kind, read three facts before applying the upsert:
   - the source changed: the incoming body differs from the base the binding held before this upsert;
   - the item changed: the shared body differs from `shared_object`, or from `base_object` until the source has folded once;
   - the two disagree: the incoming body differs from the shared one.

   An item holding no body has changed for a binding whose `shared_object` names one, and an upsert carrying no body over an item holding one disagrees with it.

   First, an upsert carrying a body over an item holding none, from a binding whose base names no body, fills the item: adopt the body, measure nothing, and leave an item conflict standing under `manual`. Under a `prefer-` policy an item conflict waiting for this body, its `conflict_object` the incoming one, is settled now: `prefer-incoming` adopts the `conflict_object`, `prefer-existing` keeps the filled body, the other kept as in step 3 over this binding's handle, the conflict cleared.

   - All three is a divergence, settled by the collection's policy: `manual` keeps the shared body, flags the item and records the incoming body in `items.conflict_object`, so every binding projects `Conflict` until an `Edit` or `Remove` settles it; `prefer-incoming` adopts; `prefer-existing` keeps.
   - A divergence where either body is unread, the incoming one not carried or the item holding none, is recorded as `manual` whatever the policy, the incoming body in `conflict_object` when carried, else left for the upgrade (§11). The policy applies once the missing body is read: the upgrade fetching the incoming one, or a fill landing the item's own (above).
   - Only the source having changed is a fast-forward; only the item having changed leaves the binding `Dirty` to propagate.
   - For an immutable kind the shared body stands and the binding's base adopts it. Flags never diverge.
3. Keep the body a policy did not adopt: the shared body `prefer-incoming` replaced, the incoming one `prefer-existing` refused, or a body a fast-forward replaces that the binding's base did not hold (a local edit `PreferRemote` dropped), and the server's body `PreferLocal` pushes over, in a write committed before that push, the binding's base moving onto it (§10). An overruling `Edit` (§11) keeps its own diverging body the same way, first, and a mutable revive with no body keeps the retained one (§5 step 7).

   `insert_item` it under `dup:`, the link id, `#` and the binding's handle, minted again while `seq_by_link` answers for the key: an earlier body kept through this binding, retained, or one this write kept first, holds it, and the second takes `dup:dup:<link id>#<handle>#<handle>`. Give it a `seq` of its own (`bump_next_seq`) and its summary and addresses, then `retain_item` with the binding's source, in the same transaction; report `Overruled`, one event per body kept, in that order.
4. Move `shared_object` to the body the item settled on when the upsert carries a body and leaves the item unconflicted. Leave it otherwise, a pull without a body and a divergence included: it is the ancestor the merge reads and stays pinned. Clear the binding's own conflict on an upsert carrying no divergence, releasing the pin its diverging body held.
5. A `Deleted` drop or a `Tombstone` upsert marks the item deleted; the dropping source loses its binding, a tombstoning one keeps it; a live upsert clears it. With no binding left, `retain_item`, then `purge_item` when another collection of the account holds the identity live with the same body, or the retiring row holds none (`held_elsewhere`). A `Superseded` or `Rekeyed` drop marks nothing.

Every other source then projects the change as its own `Dirty` or `Tombstone` and pushes it on its next run. A source lacking the item is offered a `Created` only when the body is held.

## 13. The queue

**Check**, as a producer, before anything is written. This is recommended, not required: the owner's drain checks the same rows again and parks what no source supports, so checking here only moves the refusal to the moment the user acts.

1. Map the action onto its capabilities (STORAGE Annex B's table):
   - a `move` of a message is `mail.message.move`;
   - a `set-flags` is one capability per flag it changes against the item's current set; an `add` or `copy` also one per flag it carries;
   - a calendar write also reads its resources, the new one of an `add` or `update` and the current one of an `update` or `remove`, for `calendar.scheduling` (attendees not all marked `SCHEDULE-AGENT=CLIENT` or `NONE`), `calendar.occurrence.update` and `calendar.online-meeting`;
   - an `add` carrying `supersedes` also maps onto the `remove` of the item it names;
   - a VTODO resource landing in a collection, by an `add` or `update` writing one or a `move` or `copy` of one, also reads `calendar.component.vtodo` there: a stated `none` refuses, no row passes.
2. Read the sources concerned: `load_item_capabilities(collection, seq)` for an action on an item, `load_capabilities(collection)` for an `add`, both for a `move` or `copy` into a collection synced by another source. A row with no capability is an undeclared source and gates nothing.
3. Refuse when a declared source has no row for a needed capability of Annex B's base set, or a `none` one for any capability. A capability Annex B added later gates only where a row states it, as `calendar.component.vtodo` does.
   - A refusal reports capability, source and `detail`; show the `detail` of a `partial` one.
   - A scheduled resource refused for want of `calendar.scheduling` can still be written once the user accepts that nobody is told: write `SCHEDULE-AGENT=NONE` on every `ORGANIZER` and `ATTENDEE` lacking `CLIENT` or `NONE`, which the drain reads as you do, the resource no longer being scheduled.
4. For an intent (Annex B.2):
   - The candidates are `list_capability_sources(account, collection, capability)` at the anchor collection: the item's own for an intent addressing one, the `parent` for a `collection-create` naming one, else any collection of the account and kind the new collection takes.
   - One candidate is the performer. Several take the user's choice if it is still listed: the latest `set-performer` pending in the queue for the account and capability before the one `load_performer` returns. Otherwise refuse with the candidates and let the user pick, once or through a `set-performer` action.
   - Write the performer into the payload's `source`.
   - A `submit` naming `copy` also needs `mail.submit.copy` from that performer; a `calendar-reply` or `calendar-cancel` naming `recurrence_id` also needs `calendar.reply.occurrence` or `calendar.cancel.occurrence`. Against an account whose sources declare nothing, leave `recurrence_id` out and refuse the occurrence.

**Enqueue**, as a producer, under a shared lock on objects.lock held across the whole procedure:

1. Write the body the action needs, if any (§4), every `X-PIMDIR-` property removed first from a resource the user did not write as it stands (STORAGE §18).
2. `BEGIN`; `ensure_collection`; at most one `store_object` followed by `pin_object`; `enqueue_action` with the action, its versioned JSON payload valid against payloads/<action>.v<v>.schema.json, the collection it targets in `target_collection` (a `move` or `copy` `to`, a superseding `add`'s `supersedes.collection`) and the body's hash in `object_hash`, the one the payload's `object` states; `COMMIT`. The statement stamps `created_at`. An `update` deciding a conflict, from a resolution command or form, states `resolves`: the `conflict_object` of each conflict it showed, read from `list_conflicted_items` and `list_conflicted_bindings`; an ordinary edit never states it.
3. Release the lock. Do not assume when the owner will run. Keep the row's id, the one `enqueue_action` inserted, to follow it.

**Follow** a row, as a producer or a reader: `load_action(id)` while it is pending or parked (`error` set); once gone, `load_receipt(id)`, whose `seq` is the item an `add` created. A performed intent has one too, its `seq` the item it left when its performer knew it. In neither, it was withdrawn or applied too long ago for its receipt.

**Declare**, as the owner, for every source it runs, before draining an action for it and again when its configuration changes:

1. `BEGIN`; `delete_capabilities(source)`.
2. One source-wide `set_capability`, under the account the source syncs for, for every capability of Annex B's base set you know of the kinds the source syncs, `none` included (`calendar.component.vtodo` only where you know the answer) and given a `detail` where the user deserves the reason.
3. One more naming a collection wherever the remote's access rights differ there (a read-only calendar, a reserved label), and on each collection the source holds for an implementation reaching only those (a provider's own reply verb, `none` source-wide).
4. `COMMIT`.

A source no longer run gets `delete_capabilities` alone.

**Drain**, as the owner:

1. `list_pending_actions`, store-wide in append order, outside any transaction.
2. Per row, with no network inside:
   - `BEGIN`; `claim_action` first. When it deleted no row, another handle applied it: end the transaction touching nothing.
   - Apply the action as the corresponding mutation of §11:
     - a payload its schema under payloads/ refuses (a member missing, of another type, or one its version does not define) parks, applying nothing;
     - an `add` or an `update` reads its body from `object_hash`, never from the payload, and parks when the payload's `object` is not that hash;
     - `add` derives the summary and addresses from the body; a live duplicate link id (`live_item_for_link`) parks, a retained or tombstoned holder revives, a message not agreeing with it minted beside it;
     - an `add` carrying `supersedes`, once that check passed, also tombstones the item it names as a `remove` would, or `retain_item` when no source binds it, nothing when it is gone, and records the pair with `supersede_item`;
     - a `move` or `copy` reads its target from `target_collection`, and parks when the column names no collection with a declared kind;
     - `remove` tombstones the shared item;
     - an item no source binds is the store's to settle, never skipped: `remove` retains it (`retain_item`); where `collection_sources` answers none, a `set-flags` or an `update` applies to it directly (`update_item`, the summary derived again, `if_match` checked, a body naming another key parked) while a `move` or `copy` parks; in a collection a source syncs, every kind but `remove` parks until a push has bound it;
     - an `update` stating `if_match` parks, naming both bodies, when the item holds another.
     - an `update` meeting a conflict, the item's or that of the binding it runs through (run it through a conflicted binding whose `conflict_object` its `resolves` names, when there is one), parks naming the conflict unless its `resolves` names each conflict's `conflict_object`; one stating `resolves` and meeting none parks too; a resolution applied settles as the `Edit` of §11 does.
   - Settle refcounts, the row's pin included.
   - `record_receipt` with the row's id and collection, and for an `add` the `seq` that `seq_by_link` answers for the key it staged; `COMMIT`.

   Now and then, `prune_receipts` with an instant at least seven days back.
3. On any failure, `ROLLBACK` first, which restores the claimed row, then in a new transaction:
   - an environment failure (busy, a body unreadable): `bump_attempts`, the row left pending until the owner's bound on attempts, then parked; an `add` or `update` is never applied without its body;
   - a store failure (a refused rebind, a constraint) or any other permanent one: `park_action` with the error, which counts the attempt itself.

   Neither stops the rows behind it.
   - An unrecognised action, a payload version you do not know, or an intent naming a source this run does not perform: skip, touching nothing, attempts unbumped, later rows proceeding.
   - An action a declared source concerned does not support (`calendar.component.vtodo` included), whatever the producer checked, or an intent whose `source` does not declare it: `park_action`, the capability and the source named in the error. This check, not the producer's, is the one that holds.
   - A `set-performer` runs `set_performer`, or `delete_performer` when it names no source, for the account of its anchor collection.

**Cancel or acknowledge**, as the owner: `cancel_action`, then `release_pins` on the hash it returns, in one transaction. Acknowledging a performed intent adds `record_receipt` to it, with the intent's id and collection and the `seq` of what it left when known, else `NULL`.

An intent whose effect is not a store mutation is at least once; the performer deduplicates.

An intent leaving a change behind, a `submit` asking for a `copy` its provider does not file itself, is replaced instead: `BEGIN IMMEDIATE`; `pin_object` on the body; `enqueue_action` of the `add` into `copy`, `\Seen` set; `cancel_action` on the intent; `record_receipt` for it, `seq` `NULL`; `release_pins` on its hash; `COMMIT`. The next drain applies the copy.

Operators read `load_parked_actions` store-wide; a reader overlays `load_pending_actions` for read-your-writes.

## 14. A reader

- **Collections**: `list_collections`, `list_collections_by_account` (`NULL` for a single-account store), `list_accounts`, each collection with its coverage (`covered_since`, `covered_until`, `covered_at`, the narrowest of its sources', `NULL` while one never closed a round): say "mail since" from it, and never call a search below it exhaustive. `list_coverage` per source, with the round under way to show a first sync filling in.
- **Mail lists by count**:
  - `count_mail` over a set of collections and the read and attachment filters, `seen` and `attachment`, `count_mail_by_day` with the reader's offset from UTC in whole minutes as `shift` (`120` for UTC+2, `NULL` for UTC days), `count_unread` per collection;
  - then `list_mail_page_filtered` around the scroll position, cursor `(sort_key, seq, collection)`, the first page with no cursor, and `get_mail_row` for one row by key; each collection of the set is read from its own order and the pages merged, so a page costs the same at any depth and whatever else the store holds;
  - to list down to a date, bind it as `since` to all four rather than cutting their rows after; undated mail falls below it, `NULL` lists everything;
  - `sum_mail` answers how many messages and bytes a `[since, until)` range holds, each message once, and how many of unknown size, `held` 0 for what a download would fetch and 1 for what a release would free, to say what moving that date back would download;
  - `search_mail` searches subject and sender with a `LIKE` pattern you escape, until the index (§15), and takes no floor; merged the same way, it reads each collection down to a page of hits, all of one that never matches.
- **A link picker**: `search_contacts`, `search_calendar` and `search_files` over a set of collections with a `LIKE` pattern built as for `search_mail`, A to Z on `(sort_key, seq, collection)`, merged the same way.
- **A listing** in natural order: `list_mail_page_desc`, `list_contacts_page_asc`, `list_events_page_asc`, `list_tasks_page_asc`, `list_journals_page_asc`, `list_files_page_asc`, cursor `(sort_key, seq)`, the first page with no cursor for the newest-first one and `''` and `0` for the ascending ones, each a seek at any depth. A mixed calendar reads three pages and merges on `(sort_key, seq)`; `component_of` says which table holds an item. `list_items_page_asc` and `list_items_page_desc` give the kind-agnostic row.
- **One item**: `get_mail`, `get_contact`, `get_event`, `get_task`, `get_journal`, `get_file`, or `get_item`. Render from the summary. Check a body against its name before you render from its bytes, and a range only after the whole file through the same descriptor (§4); a `NULL` body, a blob file gone under a purge, or one failing its name (STORAGE §7), is not hydrated and not an error.
- **A sweep** that must see every row once: `list_items_page`, cursor on link id.
- **People**: `list_address_placements(address, role, after_key, after_seq, after_collection, after_role, limit)`, `role` `NULL` for any, newest first, once per role, the next page from the last row's `sort_key`, `seq`, `collection` and `role`; `list_domain_placements` for a domain, by scan.
- **Identity across collections**: `list_link_placements(link_id)`, `list_object_placements(hash)`, `seq_by_link`.
- **Replies**: `list_replied(ids)`, the message ids among the bare ones of the `ids` slot that a live mail answers, its `mail_in_reply_to` rows naming them, mail under the `sent` or `drafts` role aside; a seek per id.
- **References**: `references_from(kind, link_id)` and `references_to(kind, link_id)`, the kind being the collection's, then `describe_endpoint` on the other end to show it (`list_link_placements` for every placement), since a reference outlives a tombstone and a retention.
  - As the owner, `add_reference` with an `origin` of `auto` for a rule's and `user` for a person's. It answers the reference as it stands, new or not, and nothing for an end the store holds no row of or one under a derived key. `remove_reference` unlinks.
  - The last row of an endpoint takes its references with it, by trigger.
- **Automatic references**, as the owner that records them:
  - after a write naming mail: `link_senders_of(link_id)` for each mail whose addresses moved; `link_invitations_of(link_id)` once its body was read and its `invitation` written; `link_sources_to(link_id)` once its summary is written;
  - after a contact write: `link_mail_from(link_id)`;
  - after a calendar item write: `link_invitations_to(link_id)` and `link_parents_to(link_id)`, and for a task `link_parents_of(link_id)` and `link_sources_of(link_id)` once `upsert_task_summary` wrote its `parent` and `mid`;
  - run them in the write's transaction or right after it; each records nothing twice and never touches a person's reference;
  - to start recording them over a store already filled, run all eight once with a `NULL` link id;
  - writing `invitation` comes with the body: walk the parts as for attachments, and take the `UID` of the first `text/calendar` part.
- **Files**: a folder is a collection of kind `application/octet-stream`, listed by `list_files_page_asc`, a file's name and type in its summary.
  - Find the account's attachments collection by its role, `attachments`, and every attachment with its message by `list_attachments_by_account(account, after_key, after_seq, limit)`, newest message first.
  - A message's attachments are `list_attachments(account, link_id)`: each row's `part` is the section to open from the message's body, or to have its source fetch alone; a non-`NULL` `object_hash` is a saved copy to open instead.
  - As the owner, a message's body enters the store when `lookup_objects` answered no row of its key in the account holding that body before the write; a move, a copy, a second label or the same body again enter nothing.
  - When it enters, unless its key is derived (`alt:`, `hash:`, `dup:`), walk its parts in document order. In the transaction storing the body, for each part carrying `Content-Disposition: attachment` that the collection does not hold yet: `insert_item` into the account's attachments collection, keyed `part:<message link id>#<section>`, with no body at `level` 1; `upsert_file_summary`; `add_reference` from the message with role `attachment`.
  - That collection is the file collection of the account with the role `attachments`, else one declared once as `<account>/\u0001attachments` with `set_collection_kind`, `set_collection_name` and `set_collection_role`, its name and its role both `attachments`.
  - Bodies held before you record attachments are never walked for them: no backfill, and a stand-in is never recomputed.
  - To save one, place the same key in a folder with its body. To write one to disk, build the path from its name only once separators, `.` and `..`, NUL, control and bidirectional formatting characters are neutralised, inside the directory you chose (STORAGE §18).
  - A stand-in goes by itself once no reference names it. A file of a device folder, or a stand-in, is deleted with `delete_unbound_item` then `release_pins`.
- **A file source**, as the owner syncing a folder: list each member under the id its server keeps across a rename (Nextcloud's `oc:id`, Drive's file id) as both handle and key, with its name, media type and length as its summary, its ETag as its revision, and no body; `Full` upgrades fetch the bytes.
  - A rename is the same handle under a new name; a plain WebDAV server with no such id is not a file source yet.
  - Conflicts follow the source's policy; keeping both is an `Add` of the local body as a new file, then an `Edit` to the server's.
- **Trash**: `list_retained_page` (cursor on `seq`, `0` first), every deleted row, `retained_at` `NULL` on one a source still binds; `count_retained`, `retained_bytes`.
- **Change**: `PRAGMA data_version` to know that something committed; `load_change_cursor` for the last stamp drawn, the purge count, the store id and the incarnation, then `list_items_changed_since` and `list_collections_changed_since` above the recorded stamp to know what, reconciling keys only when `purges` moved, a rename included. Another id or incarnation than you recorded, or a recorded stamp above the one it answers, is a reset: rebuild what you derived from the store as it stands.
- **Sync state**: `list_sources`, `list_coverage`, `list_conflicted_bindings(account)`, `list_conflicted_items(account)`, `load_kind`.
- **What can be done**: `load_capabilities(collection)` and `load_item_capabilities(collection, seq)` to grey out what a source cannot push before the user tries; `list_capability_sources` and `load_performer` to show who sends or replies for an account.

Never present a deleted row as live outside the trash view.

## 15. The indexer and the query client

SEARCH §3 names each statement under queries/search/ and the profile running it.

**Refresh**, as the indexer, holding an exclusive lock on index.lock, taken as §2 takes the owner lock, and no store lock:

1. Open index.db read-write, `0600` when you create it, with `PRAGMA secure_delete = ON`, and attach pimdir.db read-only as `store`. `load_index_meta`, and `load_change_cursor` from the store before the pass: the last stamp drawn, the purge count, the store id and the incarnation.
2. Read `shape` and `format_version` first. An index.db with no `index_meta`, of another shape than yours, or at a later version than yours: refuse it, naming both, and touch nothing; deleting it is a person's choice. Versions order drafts by number, every draft below every release.
3. Rebuild an index of your shape at an earlier version or lacking `format_version`, or at yours with another tokenizer, a schema text differing from migrations/search/0001_init.sql's (each table, index and trigger it creates, by name, compared by its `sqlite_master` text, `--` comments dropped and whitespace collapsed, FTS5's shadow tables and your own tables left out), a `store_id` or `store_incarnation` other than the store's, or a `store_change` above its last stamp: delete index.db, apply migrations/search/0001_init.sql, `init_index_meta`, which records this draft, the canonical shape, the store's id and its incarnation, then `set_tzdb_version` with the version of the time zone database in use and `set_floating_zone` with the zone you read floating times in, `UTC` when you state none.
4. `load_missing_items`, then `load_changed_items` above the `store_change` recorded by the previous pass, in stamp order, in bounded batches, one index transaction each. A batch may record the `changed` of its last row through `set_index_cursor`, with the purge count the last completed pass recorded. Per row:
   - Fold every text you write into `object_text` and `summary_text` under SEARCH §5 (lowercase, NFD, the marks of U+0300 to U+036F dropped, NFC), the tokenizer folding none; cut the chunks from the text before the fold.
   - `object_indexed`, else read the body, verified (§4), extract it under SEARCH §6, walking a message's parts within the depth and the count STORAGE Annex A.1 bounds them by, the role fields beside `people`, and `insert_object`, with whether the `attachment` field holds any text and, for a card, whether it holds a `TEL`, an `ADR`, a `BDAY` and a `PHOTO`, plus `insert_object_text` and, for a card, `insert_object_category` for each of its folded `CATEGORIES` values, then `insert_chunk` for each chunk SEARCH §6 cuts the `body` and `note` fields into. A blob that is not there or fails its name writes no `object` row: index the placement as bodiless and `insert_missing`; one you index now, or that holds no body any more, `delete_missing`;
   - `upsert_placement`;
   - `delete_summary_text` then `insert_summary_text` for a bodiless row, and `delete_summary_text` once it has a body;
   - `replace_flags` then `insert_flag`;
   - `replace_occurrences` then `insert_occurrence` within the horizon when the body changed, within SEARCH §7's bounds on the occurrences an item writes and the periods a rule is followed for, then `set_cut` with where either bound stopped it, `NULL` when none did;
   - `upsert_message` for the message and for every parent id it names, and `upsert_thread`, re-keying a thread on join by its lowest present `(sort_key, link_id)` member, the new row written and the members repointed before the old row is deleted;
   - a deleted row: `delete_placement`, which takes its flags, occurrences and `missing` row by cascade, then `delete_summary_text` by the id it returned, and, for a mail placement that held its link id last, the prune of step 6.
5. When `purges` moved from the recorded `store_purges` (a purge, a collection and a rename each move it): `placements_gone` and `objects_gone`, then `delete_placement` for each placement, pruning as step 6 does for a mail placement that held its link id last, and `delete_object` (the FTS row, by rowid) then `delete_object_row` for each body, which takes its chunks by cascade.
6. The prune of a message's thread, `thread_of` naming it: `unparent_messages`, then `prune_messages`, then `thread_rows` and, for each connected set over the rows left (a row and its parent), `upsert_thread` named by its row with the lowest `(sort_key, link_id)` among those with a sort key, `upsert_message` repointing its rows, and `delete_thread` for each old id, which keeps one a row still names.
7. When the horizon rolls, the time zone database names a version other than the recorded `tzdb_version`, or you read floating times in a zone other than the recorded `floating_zone`: `items_to_reexpand` bound to the old and the new horizon (the same one twice when it did not roll), the version in use and your zone, re-expand those alone, then `set_horizon`, `set_tzdb_version` and `set_floating_zone`.
8. `set_index_cursor` with what step 1 read from the store, its stamp as `store_change` and its purge count, in the transaction that completes the pass.
9. After a pass deleting what an erasure purged (§7), `optimize_text`, which merges every full-text segment so the deleted rows' words go, then `PRAGMA wal_checkpoint(TRUNCATE)`.

**Query**, as a client, on index.db read-only with the store attached:

1. `load_index_meta`, and refuse an index whose `shape` or `format_version` you do not implement, naming both; while SEARCH is a draft you implement your own draft alone.
2. Parse the query under SEARCH §8.3, answering a refusal as SEARCH §8.4 shapes it: the length, then the phrases, then the parentheses and their nesting, then the terms and operators in reading order with their count, each bounded by SEARCH §8.3's table, the first fault found.
3. Compile it. Structured terms go to seeks: `list_address_placements` on the store for an address, every page of it, a range on the sort key, `flagged`, `occurring_between`, `thread_members` in the query's account, `status:` and `priority:` to `task_summary` and a task's `category:` to `task_category` on the attached store, and a card's `category:` to `categorised`. A text term goes to `match_objects` and `match_summaries` as one FTS5 string (SEARCH §8.5): its folded text between `"`, each `"` doubled, ` *` after it for a trailing wildcard, behind `{` its field's column `} : ` for a field term, so `subject:^sync` is `{title} : "^sync"`; nothing of the query reaches FTS5 otherwise.

   `has:attachment` reads the mark for mail and `attached` for a calendar item; `has:phone`, `has:address`, `has:birthday` and `has:photo` read `holding`; `id:` with digits alone names a `seq` and a link id both.
4. Intersect, and order by the store's sort key. For a page rather than every hit, either walk the store's pages under the structured terms and probe each row's text terms (`match_object` for its body, `match_summary` for a bodiless one) until the page is full, resuming from the store's cursor, which suits a common term; or read a rare term's matches first and order them. By relevance, read `match_objects_ranked` a page of bodies at a time, keeping the hits the other terms hold.
5. Present each hit through `hit` with a snippet cut from its body's chunks (`chunks_of`), re-chunking the text you extract when another implementation built the index.
6. Report beside the result `coverage` over the query's collections (bodiless mail, contacts and calendar items, never files), `behind` (the stamps the index has yet to fold, store-wide), whether a date range left the horizon (only when the query can reach a calendar item), for a dated query `cut_before` over its collections at the range's end, and the temporal axis, from `list_coverage` for each queried collection against the query's date range.

**Agenda**, as a client drawing a range of calendar time: `occurrences_between` over the range, in the order it answers, then each item's summary row from the store (`get_event`, `get_task` or `get_journal` by its `seq`), and its body only to open it. Say when the range leaves the horizon (`load_index_meta`), and when it reaches past an item's cut (`cut_before`).

Tagging goes through the queue as a producer (§13), never through the index.

## 16. Running the vectors

- **vectors/objects.json**: for each case, name the body under BLAKE3 and compare digest, name and path, one shard directory deep. Every store implementation, before anything else.
- **vectors/payloads.json**: validate each payload against payloads/<action>.v<v>.schema.json and compare with `valid`; a producer writes none it refuses, an owner parks every one it refuses.
- **vectors/summaries.json** with vectors/fixtures/, per kind written:
  - read each fixture as bytes (they are CRLF, but for the lone `\r` three line-end cases hold, and a text-mode read changes the object name) and check its stated hashes first;
  - derive the link id, summary row, address rows and sort key, a message's header read by Annex A.1's parses and a zoned time through the resource's `VTIMEZONE`, else the IANA database, else as floating, and for mail the attachment mark without the body (`meta_attachment`) and the parts its stand-ins name (`attachments`); compare as parsed structures;
  - a case with a `hint` and a `handle` checks the minted key; one with no `uid` checks the `hash:` key, one with no `message_id` the `alt:` key.
- **vectors/sync/**, every engine:
  - build the `store` rows: summaries included, a source's round and coverage, a binding's round stamp, the `supersessions` rows; an object stated `corrupt` is its row and a file under its name holding other bytes;
  - run the `run` verb under its scope against the `remote` answers: one `snapshot` or a round's `pages`, preceded by the `head` a resumed round lists when `heads` offers one, asked from its `from` or `since` and refused when `rejected`;
  - a mutate run passes its `mutation`, an `Edit` with its `if_match`, `overrule` and `resolves` where stated;
  - the remote cut after `interrupted_after` pages, the head not counted, the stored cursor refused when `cursor_rejected`, a checkpoint bound to no scope when `scope_bound` is false, a round's pages narrowed by a date filter when they say `narrowed`, the last handing the unfiltered handles it states as `enumerated`, and a member carrying its body, its meta's fixture, when it states `carries`;
  - compare the pushes in order with their keys, feed back the `outcomes`, compare the `events` and the rows after, `changed` stamps and `retained_at` instants excluded, chunks concatenated; an `Overruled` event names the key minted again over every key held, vectors 104 and 105 keeping two bodies through one binding. An object stated after the run is compared as its row and its file: one stating neither `blob` nor `corrupt` holds bytes hashing to its name (vector 130).
- **vectors/search/**, every index:
  - build the fixture store from store.json, index it at the file's `now` stating no zone, so floating times read in UTC, run each query with its sort;
  - compare hits as `(account, seq)`, ordered where the case says `ordered` (a `relevance` case as a set on a shape ranking by no bm25), the threads of a threaded case, and the coverage, `horizon_left` included, and the temporal coverage where a case states `temporal`, after writing each collection's `sources` coverage rows, and the `cut_before` count where a case states `cut`;
  - a refusal compares its `code`, `start` and `end`;
  - list each window of `occurrences` with `occurrences_between` and compare its rows in order;
  - cut each text of chunks.json into chunks and compare the boundaries.

Read each file's `v` first and stop on one you do not know. checks/vectors.py validates the files' structure and references without an implementation; only an implementation runs a case. Vendor vectors/ and payloads/ if the build cannot read them in place, and in CI check the copy against vectors/manifest.json, its manifest against this repository's at the revision you follow, and the cases you ran against the manifest's counts (vectors/README.md).
