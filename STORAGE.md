# Pimdir storage specification

Status: storage-v1.0.0, the base, requiring no other part, released together with the sync and search parts

The storage part of the pimdir standard, and its base: a **SQLite database** (the index and the mutable state) plus a **content-addressed blob directory** (the bodies). The two layers over it are [SYNC.md](./SYNC.md), how sources reconcile through the store, and [SEARCH.md](./SEARCH.md), the index and query language over it.

This part binds every implementation, by the profile it meets (§17): a **reader** opens the store and lists it, a **producer** also appends actions, an **owner** mutates it. The two layers presuppose the store: an implementation MAY omit either and MUST conform to those it offers.

**The schema is the contract.** The tables, columns, constraints, triggers and views of [migrations/storage/0001_init.sql](./migrations/storage/0001_init.sql) are normative. This part says what a row means, how a writer sets what the schema leaves to it, what a reader may rely on and what the triggers keep. It names no statement: the SQL an implementation runs is its own (§4.4). A blob is immutable: a body edit writes a new blob and repoints the item. [OVERVIEW.md](./OVERVIEW.md) explains the model; it is informative and this part wins on any disagreement.

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in BCP 14 (RFC 2119, RFC 8174) when, and only when, they appear in all capitals, as shown here. Every statement of behaviour in this part is normative: a key word marks its requirement level, and a statement carrying none binds as one carrying MUST. Notes, examples and rationale are informative: a paragraph opening with *Note:*, an instance given in parentheses or after "for example", and a reason given with "so", "since" or "because", none of which adds a requirement.

## Contents

1. [Goals](#1-goals)
2. [Terminology](#2-terminology)
3. [Store layout](#3-store-layout)
4. [The database](#4-the-database): [requirements](#41-requirements), [schema version](#42-schema-version), [tables](#43-tables), [queries](#44-queries), [the change feed](#45-the-change-feed), [the owing marks](#46-the-owing-marks)
5. [The blob store](#5-the-blob-store)
6. [Migrations](#6-migrations)
7. [Integrity](#7-integrity)
8. [Concurrency and ownership](#8-concurrency-and-ownership)
9. [Identity and dedup](#9-identity-and-dedup): [the public id](#91-the-public-id-seq), [accounts](#92-accounts), [the sort key](#93-the-sort-key)
10. [Sync model](#10-sync-model)
11. [Retention](#11-retention): [requirements](#111-requirements), [purging](#112-purging), [evicting below a date](#113-evicting-below-a-date), [releasing bodies below a date](#114-releasing-bodies-below-a-date), [erasing](#115-erasing)
12. [Collection generation](#12-collection-generation)
13. [Encodings](#13-encodings)
14. [Operations](#14-operations): [reading the store](#141-reading-the-store), [references](#142-references), [files](#143-files)
15. [Action queue](#15-action-queue): [producing](#151-producing), [applying](#152-applying), [actions](#153-actions), [reading the queue](#154-reading-the-queue), [cancelling and acknowledging](#155-cancelling-and-acknowledging), [capabilities](#156-capabilities)
16. [Test vectors](#16-test-vectors)
17. [Conformance](#17-conformance)
18. [Security considerations](#18-security-considerations)

[Annex A](#annex-a-summaries-normative) fixes the summary and `sort_key` derivations, [Annex B](#annex-b-capabilities-normative) the capabilities and the intents' payloads. Both are normative.

## 1. Goals

Pimdir is what most PIM stores already are (Apple Mail, Thunderbird, notmuch): an indexed binary store for state, the large immutable content beside it. It is **generic**, one store for every kind the standard names, keyed by media type, a closed set that grows only by a change to this standard; **indexed**, hundreds of thousands of items and never a file open per item; **portable**, the SQLite file being byte-identical across platforms; **transactional**, a flag change or a multi-item move being one commit; and **recoverable**: what a source holds (its items, bindings, summaries and bodies) is restored by re-sync (§7).

The rest exists only in the database: un-pushed edits and pending creates, the queue and its receipts, references (§14.2), properties (§4.3), capabilities and performers, retained rows, and the collections no source syncs (§14.3). A rebuild is therefore never automatic: an implementation offers it only as an operation the user confirms, reporting first what it loses.

## 2. Terminology

- **Store**: a directory holding one database and one blob directory.
- **Collection**: a mailbox, address book, calendar or folder; a row of `collections`. Its **kind** is its media type, one of §13's four, which every item it holds shares. Its **account** is the owner-chosen id in `collections.account`, `NULL` in a single-account store (§9.2).
- **Item**: one message, contact, event, task, journal or file.
- **Placement**: one item's presence in one collection, its row of `items` keyed `(collection, link_id)`, with the binding of each source syncing it there. One item in two collections is two placements sharing one `seq` and one object. SYNC.md projects one per source, a **projected placement** (SYNC.md §2).
- **Summary**: what a reader lists an item from without its body, its row of `summary` and its rows of `summary_value`, derived by the writer, never by the store (Annex A). Its `component` is the item's **summary kind**: mail, contact, event, task, journal or file. An **address** is one person an item names in one role, a `summary_value` row of an address role (Annex A.6).
- **Mutable**, **immutable**: a card, a calendar resource and a file are mutable, an edit replacing the body under the same key; a message is immutable, one identity being one body (§11.1, SYNC.md §3).
- **Tier**: what a placement holds of its item: `Meta`, its identity, summary and sort key (`level` 1), or `Full`, the body too (`level` 2).
- **Object**: a content-addressed, immutable body: a row of `objects`, bytes in a blob file named by its **hash** (§5).
- **Handle**: the backend's id for a placement in its collection (an IMAP UID, a DAV resource name).
- **Link id**: the item's key in its collection, assigned from the identity hint the content states (`Message-ID`, `UID`) and equal to it unless the collection already holds it (§9). A key is **held** in a collection when a row of `items` there has it, live, tombstoned or retained, and **free** otherwise.
- **Pending create**: a binding with no base, a source's create waiting for its add to be accepted, under a **provisional handle**: `U+0001` followed by the link id, a name no server hands out (SYNC.md §2). A **delivered create** is one its source took before any listing named it: its binding keeps the provisional handle and holds a base naming nothing.
- **Source**: one remote the store syncs a collection with or performs an intent through, under an owner-chosen id, never empty, naming one remote store-wide. An item's sources are those binding it. Its **checkpoint** is its opaque cursor (QRESYNC state, JMAP state, DAV sync-token).
- **Batch**: the operations a writer folds into the store in one transaction, in order (§14); an operation cut into several batches writes them as its **chunks**.
- **Scope**: `[since, until)` on a message's summary `date`, either bound open, under which a source syncs a mail collection; a **round** lists a scope in pages, and the **coverage** is the scope of the last round that closed (§10, SYNC.md §5).
- **Retained item**: an item no source holds any more, kept and hidden until purged (§11).
- **Writer**: whoever writes rows of the store: the owner, an engine through it (§14), a producer enqueuing (§15). A **consumer** derives state from the store and follows its change feed (§4.5). An **engine** is an owner's program reconciling the store with its sources through **connectors** (SYNC.md §4).
- **Owner lock**, **staging lock**: the advisory locks on owner.lock and objects.lock (§8).
- **Action**: a mutation a producer appends to the queue for the owner to apply (§15.3); an **intent** is one a single source, its **performer**, performs outside the store (Annex B.2). A **capability** is something a source can push or perform (§15.6).

## 3. Store layout

```
mystore/
  pimdir.db            the SQLite database (may be accompanied by -wal / -shm)
  owner.lock           the owner lock, held exclusively (§8)
  objects.lock         the staging lock, held shared by producers (§8)
  objects/             the content-addressed blob directory (§5)
    ab/abcd…            a body, at objects/<hash[0:2]>/<hash>
  quarantine/          the bodies that failed their name, kept, never read (§7)
  local/               the owner's own state, which this standard never defines
  index.db             the search index, when one is built (SEARCH.md)
  index.lock           its indexer lock
```

A directory is a pimdir store if and only if it contains a pimdir.db whose `store_meta.format` is `'pimdir'`. The lock files are empty, created by the first handle that takes one. quarantine/ is created by the first move into it. The index is derived and droppable.

local/ is the owner's, for the state it keeps beside the store, created with mode `0700` (§18) when it first needs it. A reader and a producer ignore it, the collector never walks it, and a backup copies it (§8). State there that follows the store is a consumer's, checked against the store's id and incarnation (§4.5).

No other file belongs in the directory: what an implementation keeps of its own is under local/ or outside it. An implementation MUST ignore a file it does not own, save the temporaries the collector removes (§5), and the collector walks objects/ only, never quarantine/ nor local/.

## 4. The database

### 4.1 Requirements

- The database MUST be a SQLite database named pimdir.db, holding the schema under migrations/storage/, which is the store's one on-disk format.
- The schema loads on **SQLite 3.18** or later: every table, index, trigger and view it creates, and every insert, update and delete into its tables, compiles there. A column's type is held by `CHECK (typeof(…))`, never by `STRICT`, and the schema calls no JSON function.
- `PRAGMA foreign_keys = ON` MUST be set per connection, so every reference of §4.3 holds, and so MUST `PRAGMA synchronous = FULL` or `EXTRA`: a commit a power loss undid would hand out again a queue id, a `seq` or a stamp already recorded (§4.5, §9.1, §15). A connection that writes sets `PRAGMA secure_delete = ON` (§11.5).
- `PRAGMA journal_mode = WAL` is RECOMMENDED for a local store, with a `PRAGMA journal_size_limit`; see §8 for a network filesystem.
- pimdir.db is created with `PRAGMA auto_vacuum = INCREMENTAL`. An owner MAY run `PRAGMA incremental_vacuum` after the collector's run, a purge, an eviction or a release (§5, §11) to give the freed pages back to the filesystem.
- A reader and a producer SHOULD set a busy timeout, so the owner's write transaction delays a read or an enqueue rather than failing it.

### 4.2 Schema version

`store_meta.format_version` names the version of this part whose schema the store holds: `storage-vN`, N its major alone (`storage-v1` for this version), written at creation and by every migration (§6). A draft of this part wrote its own name, `storage-draft-NN`.

**A draft's store is refused.** A program of any profile MUST refuse a store whose `format_version` names a draft, naming both versions, and a store lacking the column, which a draft before storage-draft-08 wrote: a draft's schema was edited in place, so its store is read by no release. A refused store is never reconciled, migrated, rebuilt, written nor deleted.

**Which store is the earlier.** Format versions are ordered: none first, then the drafts by the number after `storage-draft-`, read as a decimal integer (`storage-draft-08` before `storage-draft-19`), then the releases by their major (`storage-v1` before `storage-v2`). A program refusing a store for its `format_version` MUST say, by this order, which of the two is the earlier, and what that asks: a store below its own was written by an earlier engine, whose queued writes it alone holds, so the user syncs it with that engine until nothing is queued, then moves its directory aside and syncs a new store; a store above its own asks for a later program. A marker this order does not read (another prefix, no number, a major with a leading zero) is named as it stands and ordered neither way. No refusal advises deleting the store. vectors/versions.json pins the order.

The schema version is `PRAGMA user_version`, mirrored in `store_meta.version`. The two MUST agree; a store where they disagree is corrupt. Both move together, only in the transaction applying a migration (§6). This part's major version is the schema version; a minor version adds a rule or a vector and breaks no store; a patch is editorial. 0001_init.sql is version 1's and never changes; a change to the schema is a migration to the next version (§6).

**Compatibility versions.** `store_meta.read_version` is the lowest schema version a program must implement to read the store, and `store_meta.produce_version` the lowest to enqueue into it (§15); each migration states which it raises (§6). Once this part is released, an owner opens a store whose `version` it knows and migrates it to its own; a reader one whose `read_version` is at most its own schema version; a producer one whose `read_version` and `produce_version` both are, each reading a store below its own version as that version defines it.

**A store above a program's version is judged by `store_meta` alone.** A released reader or producer opening a store whose `version` is above its own MUST judge it by six columns of `store_meta` and by nothing else of the schema: `format` is `pimdir`; `format_version` is `storage-v` followed by `version`; `version` equals `PRAGMA user_version`; `read_version`, and for a producer `produce_version` too, is at most its own version; `hash_algo` is one it knows (§6 step 2). No migration renames, drops nor redefines these six. Such a program MUST NOT refuse the store, nor read it as corrupt, for a `user_version` above its own, nor for a table, a column, an index, a trigger or a view it does not know: its SQL names its columns (§4.4), so what that version added moves nothing it reads or writes. What it compares of the schema's text is §18's.

A program judging whether it opens a store at all (here and §6 step 2) MAY read `store_meta` with `*`, taking each column it knows by name, the row it judges being perhaps another version's: the one exception to §4.4's column rule.

### 4.3 Tables

The schema holds each table's columns, types and constraints, §13 their encodings.

- **`store_meta`**, one row: `format`, `format_version`, `version`, `read_version`, `produce_version` (§4.2); the store's identity `store_id` and `incarnation` (§4.5, §8); `hash_algo` (§5); `created_at`; `derivation` (§6); `sync_version` (§14); the counters `next_seq` (§9.1), `next_change` and `purges` (§4.5).
- **`collections`**: `id`, `account` (§9.2), `kind`, `name`, `parent`, `color`, `description`, `sort_order`, `role` (§14), the cross-source `conflict` policy, `generation` (§12), `changed` (§4.5). Every foreign key onto `id` is `ON UPDATE CASCADE`; `ON DELETE` is `CASCADE`, but `SET NULL` for `parent` and a receipt's `collection`, and `RESTRICT` for a queue row's `collection` (§14).
- **`sources`**: one row per source syncing a collection, keyed `(collection, source)`: its `checkpoint`, its coverage and its round (§10). The schema holds that no coverage carries no bound and no open round carries nothing. A source id names one remote store-wide, so an owner filing two accounts keeps their source ids apart (§9.2).
- **`capabilities`**, **`performers`**: what each source can do, per `(source, collection, capability)`, `collection` `NULL` for the source-wide row, and the source chosen per `(account, capability)` (§15.6).
- **`objects`**: `id`, `hash`, `size` and `refcount` (§5). `id` is the key every pointer at the object carries, drawn above every one before and never reused. It is the store's own: an implementation MAY carry an `id` within a transaction, and none shows one; outside the store a body is named by its unique `hash` (§4.4).
- **`items`**: one placement, keyed `(collection, link_id)`, its `id` the key its children carry, never reused nor shown (a consumer keeps `(collection, seq)`): `seq` (§9.1); its flag set `flags_known`, `marks`, `keywords` (§13); `object`, its body; `sort_key` (§9.3); `level`; `deleted`, `conflicted`, `conflict_object` (§10); `retained_at`, `retained_by` (§11); `changed` (§4.5); `lacks` (§4.6).
- **`bindings`**: one source's binding of an item, keyed `(item, source)`, its `collection` held equal to the item's by a foreign key onto `items(id, collection)`: `handle`; the base `base_present`, `base_flags_known`, `base_marks`, `base_keywords`, `base_object`, `base_revision`; `shared_object` (§10); `server_object_id` (SYNC.md §4); `conflicted`, `conflict_revision`, `conflict_object`; `round` (§10); the refusal `refusal`, `refused_key`, `refused_at` (SYNC.md §5); `owes` (§4.6). A handle names one item per source and is never repointed: `bindings_by_handle` is unique (§10).
- **`summary`**: an item's summary (Annex A), at most one row per item, cascading with it, referencing no object: `component`, `uid`, `title`, then each component's columns.
- **`summary_value`**: a summary's lists, keyed `(item, role, position)`, cascading with the item: addresses under their roles, a message's `in-reply-to` ids, a task's `category` values (§13).
- **`item_reference`**: a reference between two endpoints (§14.2), held by no foreign key, with its `role`, `origin` and `created_at`.
- **`item_property`**: an item's **properties**, local state no source carries, one row per value, keyed `(seq, key, value)`, so they follow the item's public id (§9.1) into every collection and account filing it, through retention, restore (§11.1) and rekey (§12). A **key** is `<namespace>/<name>`, each part of `[a-z0-9._-]`, at most 64 bytes; a **value** is 1 to 1,024 bytes of UTF-8 holding no NUL; an item holds at most 64 values under one key; the schema refuses each past its bound. `pimdir/` is the standard's namespace: `pimdir/label` holds the item's **labels**, which `tag:` never reads (SEARCH.md §8, §10); every other name under it, `pimdir/session-key` included, no program writes until a version defines it. An application writes under its own name (`himalaya/snooze-until`). A label is kept as written and matched folded (Annex A.2's fold): an item holds no two labels of equal fold. Every other key's values compare byte for byte. A property names a `seq` some row of `items` holds, live, tombstoned or retained, which a trigger holds, and goes with the last such row (`items_drop_properties`). A value added or removed stamps every row holding the `seq` (§4.5). A property is never read by the sync part, never in a binding, never pushed (SYNC.md §3); the owner writes it applying a `set-property` (§15.3) or on its own account on the same terms.
- **`supersessions`**: the item an `add` carrying `supersedes` tombstoned and `by_item` the item it created (§15.3), each end cascading with its item.
- **`queue`**, **`receipts`**: the action queue and what an applied row or a performed intent became (§15).

An item plus one binding per source is the whole model. Single-source is the N=1 case; N≥2 adds only `deleted`, a removal that lingers until every source has dropped it. The schema's indexes are part of it; no index orders the items of several collections together (§9.3).

### 4.4 Queries

The standard binds no statement. The SQL an implementation runs on the store is its own, on any SQLite the schema loads on, bound by the schema, by this part's rules, by §7's invariants and by the vectors (§16). Writes a rule puts in one transaction may be any number of statements, no other connection's write coming between them.

**A statement names its columns.** No statement run on the store reads `*` or inserts without a column list, so SQL written against one schema version survives the columns a later migration adds, which is what lets such a migration raise no compatibility version (§6). The one exception is §4.2's.

**A body is named by its hash.** Every column naming a body holds its object's `id`. A writer resolves a body's hash to that `id` within its transaction, a hash naming no object row being refused, never written as no body; a reader answers a body as its hash and opens its blob by that name (§5).

### 4.5 The change feed

`items.changed` and `collections.changed` hold the value of `store_meta.next_change` the row took when it last moved. The counter only increases and every stamp is drawn once, so a page ordered by `changed` is total. The schema's triggers draw the stamps: an insert takes the next; an update takes one only when a column a reader can observe moved, `marks` and `keywords` among them; a property added or removed stamps every row holding its `seq`; a row written again as it was stamps nothing.

A `summary` or `summary_value` row has no stamp: a writer changing one under an unchanged item MUST request the item's stamp in the same transaction, by setting its `changed` to `-1`, which the trigger replaces with the next stamp. A renamed collection restamps every item under its new id, and a source's coverage moving restamps its collection.

A deleted row cannot carry a stamp, so a purged or evicted item (§11.3), a collected object and a deleted collection count in `store_meta.purges`, the delete triggers raising it, and so does a renamed collection, its items' keys under the old id being gone.

A consumer records the last stamp drawn (`next_change` less one), `purges`, `store_id` and `incarnation`; on its next look it folds the items and collections stamped above it, and reconciles its keys only when `purges` moved. It reads a cursor before a pass and records it after.

**A reset.** A consumer finding another `store_id` or another `incarnation` than it recorded, or a recorded stamp above the store's last stamp drawn, MUST treat what it derived as unknown and reconcile in full, or rebuild, from the store as it stands. A producer following a queue id (§15.4) records the store's id and incarnation with it and checks them the same way.

### 4.6 The owing marks

What a delta loads beside what it lists (SYNC.md §10) is named by two marks, so that read costs what is owed:

- **`bindings.owes`** is 1 while the placement may owe a push or a decision (SYNC.md §3): the binding or its item conflicted, the item deleted, no base, a known flag set differing from a known base set, or the item holding a body other than `base_object`. A superset of the placements not `Clean`.
- **`items.lacks`** is 1 while the item is live, holds a body, and a source with a `sources` row on its collection binds it not.

Each mark is a rule the schema writes once, as the view `binding_owes` or `item_lacks`, which its triggers compute again after every write that can move it, so a mark equals its rule at the end of every statement. A writer MUST NOT write either column, and an implementation creating the schema from text of its own MUST keep every input of a rule moving its mark, as it keeps the stamps (§4.5). A source no `sources` row names counts in no lacking mark: what it lacks is read by walking the collection.

## 5. The blob store

Bytes live under objects/, one file per hash, at `objects/<hash[0:2]>/<hash>`: one level of shard directories, each named by the first two characters of the names it holds. The name and the path are normative (§16). The digest is BLAKE3 at its default 32-byte output over the raw bytes, the only one (`store_meta.hash_algo` `blake3`, a closed vocabulary, §13). The name is the digest in RFC 4648 §6 base32, lowercased, unpadded: 52 characters of `a` to `z` and `2` to `7`. The empty body is a real object.

**A name is never a path.** An implementation MUST check a name against the alphabet and the length before it builds a path from it, wherever it read the name: a row, a payload, a directory entry, a remote's answer. Where the platform allows it, it MUST NOT follow a symbolic link when it opens a shard directory or a blob (`O_NOFOLLOW`, with `O_DIRECTORY` through `openat` for the directory, or `lstat` before the open): a link found where either belongs holds no body, and an owner moves it into quarantine/ as §7 moves a body failing its name.

**Write** never replaces: a period-prefixed temporary file in the shard directory, named uniquely to the writer, `fsync`, a move onto the final name that fails when the name exists, then `fsync` the directory, and objects/ too when the write created the shard directory. The move is `link(2)` then `unlink(2)` of the temporary, `renameat2` with `RENAME_NOREPLACE`, or the platform's no-replace move (below); never `rename(2)`. The blob write MAY precede the transaction writing its row and SHOULD for a body of any size: the writer's lock (§8), not the file's age, keeps a collector out of the window. A body streamed to its path is written the same way, named by the digest of the bytes streamed. Every period-prefixed regular file under objects/ is a writer's temporary, and no implementation keeps another file there; a writer unlinks its own once its move is made or has failed.

**An exclusive create and copy** is the one move that is not atomic, and a writer MAY use it only where no atomic no-replace move is offered or allowed (on Android before API 30, or where `renameat2` refuses `RENAME_NOREPLACE`): the final name created with `O_CREAT | O_EXCL`, the temporary's bytes copied into it, the file `fsync`ed, then the temporary unlinked. A copy that fails unlinks the part it created; a part a crash left behind fails its name (§7) and is set aside by the next write of that body.

**A name held is verified.** When the final name exists, the writer MUST verify the file already there against its name (§7) before it keeps it, and so MUST a writer that skips its write because it finds the name or its row there; it flushes the shard directory all the same before the row naming the body commits. A file that passes is kept and the temporary unlinked. A file that fails is never kept: an owner moves it into quarantine/ as §7 does, holding the staging lock exclusively, after verifying it again under the lock, then makes its move again; a producer fails its write and enqueues nothing, reporting the name. Any other failure of the move fails the write.

**Reference counting**: `objects.refcount` MUST equal the number of pointers at the object across `items.object`, `items.conflict_object`, `bindings.base_object`, `bindings.conflict_object`, `bindings.shared_object` and `queue.object`, maintained in the same transaction as the writes, a producer's enqueue included (§15.1). `bindings.shared_object` names the common ancestor an engine merges from (SYNC.md §9), so it MUST outlive the item's own body until every binding has reconciled against what replaced it: one body per binding, released when the binding agrees with another. The one exception is a message body a release frees (§11.4): a message never diverges (SYNC.md §9), so no merge reads an ancestor of it, and a `shared_object` naming that body is released with it.

**An unreferenced object is not a deleted one.** A write MUST NOT delete a row at refcount zero nor unlink its blob: a consumer MAY index a body in one batch and attach it in a later one.

**The collector** is one operation, run when asked:

1. It MUST recount every object's pointers first (§7), so a count a writer left behind is settled before anything is judged by it.
2. It deletes the object rows at `refcount <= 0`.
3. It walks objects/ and unlinks every file no row names: only a regular file, read by `lstat`, whose name is well-formed and begins with the two characters of its shard directory, itself a directory and not a link, named by two characters of the alphabet.
4. It unlinks every period-prefixed regular file it meets there, read by `lstat`, and reports each.
5. It leaves anything else in place and reports it, flushes every directory it unlinked in before it answers, and never walks quarantine/ nor local/.

It MUST hold the owner lock and take the staging lock exclusively (§8), which proves no other process is between a body and its row, nor between a temporary and its move. It MUST NOT run while one of the owner's own verbs is between two chunks (§14): a body streamed in one chunk and attached in the next is a row no pointer names yet. Scheduling it is the owner's.

**Other platforms.**

- On Windows, the no-replace move is `MoveFileExW` without `MOVEFILE_REPLACE_EXISTING`, with `MOVEFILE_WRITE_THROUGH`, or `CreateHardLinkW` then deleting the temporary; a directory has no `fsync`. A file another process holds open is deleted only when that process opened it with `FILE_SHARE_DELETE`, its name taken until the last handle closes. A reader SHOULD open a blob so; an unlink the collector cannot make is left for the next collection, the row being gone already, and a write meeting a name still taken fails and is tried again, as any other failure of the move.
- On macOS, the temporary and the directory are flushed with `fcntl` and `F_FULLFSYNC`, and the no-replace move is `renamex_np` with `RENAME_EXCL`, or `link(2)`.
- *Note:* on Android, where an app is denied `link(2)` on its own files, the move is `renameat2` from API 30 and the exclusive create and copy before it.

## 6. Migrations

Schema evolution is ordered, forward-only SQL under migrations/storage/, named NNNN_description.sql, NNNN the version it brings a store to. Once version 1 is released, every change to the schema is a migration to the next version, which states the compatibility versions it raises (§4.2), each to its own number, `version` being raised by every one:

- neither, for an index, a table, or a column a reader may ignore: nullable, or `NOT NULL` with a default;
- `read_version`, for a renamed or dropped column or a changed meaning: a value added to a closed vocabulary (§13), a column read otherwise than before;
- `produce_version`, for a `NOT NULL` column without a default on a table producers write (`queue`, `objects`, `collections`), or a new rule on what a producer enqueues (§15).

An added column raises neither only because every statement names its columns (§4.4).

An owner opening a store runs these steps in order, and nothing else changes the schema:

1. Read `PRAGMA user_version`, `0` for a fresh database, which goes to step 3.
2. Read `store_meta`. A store §4.2 says the program does not open MUST be refused, naming both versions: a draft's store, a store lacking `format_version`, a released store above the highest version the implementation knows. So MUST a store whose `hash_algo` the implementation does not know, naming it (§7). It is never reconciled, migrated, rebuilt nor written.
3. For each migration above the store's version, in order: open a transaction, run the script, set `user_version` and the versions of `store_meta` the migration states, commit. A failed script rolls back and stops. A fresh database writes the `store_meta` row in the transaction applying 0001_init.sql.

**A migration that rebuilds a table.** SQLite changes a table's constraints, and on the floor (§4.1) drops or renames a column, only by a rebuild, and with foreign keys on dropping a table deletes or nulls every row referencing it, with no error. A rebuild MUST NOT run in one transaction with foreign keys on, as step 3 runs any other migration. A migration states that it rebuilds, and then:

- the runner sets `PRAGMA foreign_keys = OFF` before it opens the transaction, and `ON` again once it has ended;
- the script creates the new table under a temporary name, with every column, constraint and `WITHOUT ROWID` clause of the old one but what the migration changes, copies the rows by named columns, drops the old table and renames the new one;
- it creates again every index and trigger of the table, and drops before and creates again after every trigger and view of another table whose text names the table;
- it keeps the table's `sqlite_sequence` row where the table is `AUTOINCREMENT`, so no id is handed out twice;
- the runner reads `PRAGMA foreign_key_check` before the commit, which MUST answer no row, and `PRAGMA integrity_check`, which MUST answer `ok`; any other answer rolls the migration back.

**A closed vocabulary grows by its `CHECK`.** A migration adding a value to a closed vocabulary (§13) need not rebuild: it MAY edit the constraint in the table's stored text, in the migration's transaction and with foreign keys on, under `PRAGMA writable_schema = ON`, replacing the `CHECK`'s text exactly and nothing else, then raising `PRAGMA schema_version` and setting `writable_schema` off, the runner reading `PRAGMA integrity_check` before the commit. Defensive mode refuses that edit (§18), so the runner leaves it for that transaction alone.

There are no down-migrations, and no implementation rebuilds a store it cannot read: it refuses it (step 2), and a corrupt one is repaired (§7) or refused. A migration MUST preserve every row of every table and the meaning of every column it keeps: the queue, the receipts, the references, the properties, the capabilities, the performers, the retained rows and the collections no source syncs hold state no source restores. A **reader** or a **producer** never changes the schema: it runs step 2 under its own profile's terms (§4.2). pimdir.db holds the schema alone: an implementation keeps state of its own outside it (§3).

**Derivations are revised.** `store_meta.derivation` names the Annex A revision a store's summaries and sort keys stand under, the creator's at creation. An owner at a later revision than the store's MUST re-derive, from every held body, the columns the revisions between them changed, paging the held bodies, and records its own revision in the transaction writing the last page; until then the re-derivation is owed and resumed at the next open. An owner at an earlier revision derives as it knows, and MUST record its own revision in `store_meta.derivation` in the transaction of its first write of a summary or a sort key, so the next owner at a later one re-derives them.

## 7. Integrity

- A store is self-checking: `PRAGMA integrity_check`, plus recomputing an object's hash against its row and file name. The refcount invariant (§5) and the foreign keys are the structural invariants; a recount settles every object in one grouped pass over the six pointer columns, zero for an object nothing names, and `CHECK (refcount >= 0)` fails a double release at the release.
- **A body is checked against its name when read.** Whoever reads a body whole (a reader, a producer, an owner, an engine, an indexer, a performer) MUST verify that its bytes hash to its name before it serves, parses, indexes, pushes or copies it, or performs an intent with it. A streamed read verifies at the end and fails on a mismatch, before its consumer commits anything built from it.
- **A range is verified by a whole read.** Whoever serves, parses or copies part of a body (an attachment opened by offset, a message's head) MUST first read the whole file through the descriptor it reads the part from, and verify it; that covers every range read through it while it stays open.
- **Failing is missing.** A body whose bytes do not hash to its name and one whose file is missing are the same state: the item holds no body. Such content is never served, parsed, indexed, pushed nor used to perform an intent: an `add` or an `update` carrying it is retried, then parked (§15.2), and the next `Full` upgrade fetches it again (SYNC.md §6).
- **A mismatch is quarantined, never unlinked.** An owner finding a body that fails its name MUST move the file out of objects/ into quarantine/, under its name, a period and a suffix unique to the move, and report it. It MUST NOT unlink it: the bytes may be the only copy of something a person can still recover. It moves it holding the staging lock exclusively (§8), serialised against its own writers, after verifying it again under the lock. The row stays, and the next write of that body lands.
- A reader or a producer finding a mismatch moves nothing: it treats the body as missing and reports it. No program reads a file under quarantine/ as a body, and only the user empties it.
- An engine MUST NOT push a body it has not verified in the run: a create or an edit whose body fails stays pending and is reported.
- A program finding a `store_meta.hash_algo` it does not know refuses the store (§6 step 2) and never verifies, quarantines, collects nor fetches a body under another algorithm.
- Blob bytes are trusted over a row, a name over bytes: a row whose size disagrees with a body hashing to its name is repaired from the body.

## 8. Concurrency and ownership

At most one process on one host owns pimdir.db at a time, and only the owner mutates the store, the §15 enqueue excepted.

An owner MUST hold an exclusive advisory lock on owner.lock for as long as it owns the store. An owner that cannot take it MUST fail immediately, naming the store, and never wait. A lock file, once created, MUST NOT be removed, renamed nor replaced while the store exists, by any program: a process opening a new file at the path would take a lock the holder of the old one does not exclude. An owner SHOULD verify, before each write transaction, that the file it holds locked is still the one at the path (on Unix, `fstat` and `stat` answering one device and one inode), and give up the store, writing nothing more, when it is not.

Every lock this standard names (owner.lock and objects.lock here, index.lock in SEARCH.md) MUST be taken whole-file on the open file: on Unix with `flock(2)`, `LOCK_EX` or `LOCK_SH`, `LOCK_NB` where a rule forbids waiting; on Windows with `LockFileEx` over the whole range (offset 0, both length words `0xFFFFFFFF`), `LOCKFILE_EXCLUSIVE_LOCK` for exclusive, `LOCKFILE_FAIL_IMMEDIATELY` where a rule forbids waiting. An implementation MUST NOT use `fcntl` or `lockf` record locks for them: on Linux those do not see a `flock` lock, and a process loses them when it closes any descriptor of the file. On macOS, SQLite's sync stops at the drive's cache unless `PRAGMA fullfsync = ON` is set, which an owner and a producer there SHOULD set.

The lock excludes other processes and nothing inside its own, so an owner MUST serialise its own collector against its own writers, and MUST release and retake the role as one operation, or it locks itself out. Two lesser roles exist, both local-host only:

- **Readers** open read-only and see consistent WAL snapshots while an owner runs. A reader MUST NOT take either lock.
- **Producers** perform the §15 enqueue transaction and nothing else, and MUST NOT assume when the owner applies it. A producer MUST hold the staging lock on objects.lock shared across the blob write and the enqueue that pins it: that is the window a collector must not run inside. It holds it across the write of an object row and its pin, whether or not it wrote the blob, and across the verification of a body it names without writing (§5), until the transaction naming that body has committed.

On a network filesystem, neither SQLite's locking nor advisory locks being reliable, a store MUST be owned by exactly one process on one host, SHOULD be enforced single-instance with a lease, and MUST use rollback-journal mode or `PRAGMA locking_mode = EXCLUSIVE`, never WAL's shared memory or `mmap`.

**Copies.** A backup MUST copy pimdir.db consistently, through SQLite's online backup API or `VACUUM INTO`, never as a file under a running owner, and then objects/, quarantine/ and local/, holding the staging lock shared across the copies so no collector unlinks a body the copied database names. It copies no temporary, no lock file and no index.db.

A restore runs with no program holding the store: it holds owner.lock, failing at once when another holds it, and the staging lock exclusively. Where a store is there it replaces it so:

- every file of the copy's objects/ and quarantine/ is put in under its name, a name already held keeping its file; a body only the replaced store named stays for the collector, so a restore unlinks no body;
- the copy's `incarnation` is raised first, by a random stride above both its own and the replaced store's when that store can be read, its `store_id` kept, so the restored store answers an incarnation no consumer recorded (§4.5) and two restores of one backup answer two;
- the replaced database, with its WAL, shared-memory file and journal, is removed only once every body is in and the incarnation raised; then local/ is replaced whole by the copy's, no owner holding a file there, and the copy becomes pimdir.db last, so a restore stopped and run again never leaves the database of one store beside the local/ of the other;
- the restored database takes the journal mode of the store it replaces, else the one an owner creates a store in;
- the lock files and index.db stay; an indexer finding another incarnation rebuilds its index (§4.5).

A live store MUST NOT be replicated by a file-synchronisation tool: each host would hold an owner lock over its own copy, and the tool would copy the database and its WAL mid-write. Devices share what a store holds through sources (SYNC.md), each with a store of its own.

## 9. Identity and dedup

Four identifiers are kept distinct: the **handle**, the backend's per-collection id; the **link id** (`items.link_id`), the item's key in its collection, internal; the **hash**, content state and blob key; and **seq**, the store-global public id a consumer keys reads and edits by (§9.1).

Annex A derives the **hint**; this section assigns the key. A hint is usable when it is not empty once trimmed of the space (U+0020) and the tab (U+0009); content stating none, or one not usable, takes the kind's fallback (`alt:` for a message, `hash:` for a DAV resource). A usable hint is the key verbatim, the trim judging it and never changing it.

**Reserved prefixes.** `alt:`, `hash:`, `dup:`, `part:` and `file:` begin the keys a writer derives (Annex A.7), and `esc:` the escape. A hint beginning with any of the six, compared byte for byte, MUST be escaped before the table below: the key is `esc:` followed by the hint (`esc:hash:0123`), minted over as any other. A connector naming the identity to its server strips the one leading `esc:`. The hint or the fallback, so escaped, is the key `k`.

**Minting.** The key **minted** over a key and a handle is `dup:`, the key, `#` and the handle, concatenated verbatim (`dup:abc@host#1174`), minted again over the same handle while held (`dup:dup:abc@host#1174#1174`). Minting yields a free key, and never lands, joins nor revives a row.

**Assigning the key.** A writer naming a member a source lists or fetches (SYNC.md §6), or staging a create (SYNC.md §7), MUST take its `link_id` from the first row of this table that matches what holds `k` in the collection. A member is minted over its handle, a create over the provisional handle it derives (§2). A handle the source already binds is no member to name: its key was resolved once, and a `hash:` key changing under it retires its binding (§10).

**Agreeing.** A row holding a message **agrees** with the member, the `Add` or the create when their summaries agree on the subject (`title`), `date` and `sender` (Annex A.1), byte for byte, `NULL` matching `NULL`, and, for a retained row, on `size` too where both state one. A row of another kind agrees with anything; a row holding no summary agrees with no message. A message that does not agree is another one reusing the `Message-ID`, and is never joined, landed nor revived. A member named from a value its source decoded by rules of its own may so be kept apart from its own message: a missed dedup, never a wrong merge.

**Across collections.** The same agreement guards a hint between the collections of an account, a row of another kind agreeing with anything: a body is linked from a row of another collection only when that row agrees with the placement, on `size` too where the placement states one, and never from one whose binding of the same source states another `server_object_id` (SYNC.md §6); a message shares the `seq` of a row holding its key elsewhere only when it agrees with it (§9.1); a retiring row holding no body is held elsewhere only by a row that agrees with it (§11.1). The last two compare subject, `date` and `sender` alone. Two members of one collection stating one hint share no body by agreement, whatever another collection holds (§14; SYNC.md §6).

| What holds `k` | A member a source names | `Add` | `Copy`, `Move` |
| --- | --- | --- | --- |
| nothing: `k` is free | `k` | `k` | `k` |
| a live item holding a pending create of this source (§2), delivered or not, under `k` or under `k` minted over the provisional handle `k` derives, `k` first, agreeing | that create's key, landing the create (SYNC.md §6) | refused | minted |
| a tombstone holding a delivered create of this source (§2) under either key, `k` first, agreeing | that create's key, landing the create (SYNC.md §6) | `k`, reviving it as a tombstone still propagating does (below) | `k`, reviving it as `Add` does |
| an item this source binds with a base under another handle, not a provisional one | minted | refused when live; a tombstone revives as below | minted when live; a tombstone revives as below |
| any other live item, other sources alone binding it or none, agreeing | `k`, joining it: the item gains this source's binding | refused | minted |
| a tombstone still propagating (`deleted` 1, other sources binding it), agreeing | `k`, joining it, which revives it, a live upsert clearing `deleted` (SYNC.md §9) | `k`, reviving it: the row adopts the new body and its delete is withdrawn on every source | `k`, reviving it as `Add` does |
| a retained row (§11), agreeing | `k`, reviving it (§11.1) | `k`, reviving it (§11.1) | `k`, reviving it (§11.1) |
| any row above but the first, holding a message that does not agree | minted, never joined, landed nor revived (enforced by the write, §14) | refused when live, else minted | minted |

A body kept apart by a policy, an overruling `Edit` or a revive (§11, §11.1) is keyed by minting over the handle of the binding that settled it. A rekey carries each key by link id (SYNC.md §8). A fallback goes through the same table: two messages stating no `Message-ID` may share an `alt:` key, two byte-identical UID-less resources one `hash:` key.

The minted form is deterministic and prefixed, so it is never pushed as a protocol identity. It is opaque: a reader MUST NOT parse it and a store MUST NOT rewrite it, since rewriting would change a `seq` a consumer has shown.

Deduplication keys on the hash: one body in two collections is stored once. Merging keys on the hint, conservatively: a missed dedup is harmless, a wrong merge hides data. A writer-derived key (`alt:`, `hash:`, `dup:`) carries no identity: it MUST NOT link a body from another row (SYNC.md §6) and MUST NOT share a `seq` (§9.1), and no reference names one (§14.2), nor a file of a part of a message under one (§14.3).

A `hash:` key names bytes, so a UID-less card edited on its server changes key under the same handle: the old item is retained, the new one is ordinary (SYNC.md §3). All four identifiers are store-wide, accounts included; an identity or a body in several collections is a fact the store reports, never a merge it performs.

### 9.1 The public id (`seq`)

`items.seq` is a small integer a consumer shows and accepts wherever it would take a link id; `(collection, seq)` is unique. A placement takes the `seq` of a row holding its link id in a collection of the same kind, whatever that row's state, for a message only a row agreeing with the summary being written (§9), the lowest `seq` when several do; otherwise it draws `store_meta.next_seq` and raises it. A `seq` only increases, is never reused, and never moves once drawn. A message whose `Message-ID` spells an event's `UID` draws its own.

One write drawing several draws them in a fixed order, so every owner numbers a batch alike: first each item its upserts name, in the batch's order, then each body the write keeps as a retained item (SYNC.md §9), in the order kept.

A minted, `alt:` or `hash:` key draws its own `seq`; the item holding the bare hint keeps the shared one. A file's `part:` or `file:` key (Annex A.7) shares its `seq` as a hint does. A `part:` key is only ever built over a message's identity, never over a derived key (§14.3). An item's properties are keyed by its `seq` (§4.3).

### 9.2 Accounts

`collections.account` is a grouping key, `NULL` in a single-account store. `collections.id` stays unique store-wide, so an owner filing two accounts namespaces their ids (`work/INBOX`) and records the account. An owner namespacing its ids MUST record the bare name in `collections.name` (§14), the separator being its own convention and not one a reader can strip. The account scopes nothing: link ids, hashes and `seq`s keep their store-wide meaning.

An owner syncing accounts in parallel processes MUST give each its own store (§8). The store records nothing else about an account (no credentials, §18, no endpoints), and learns one from its collections. An owner that namespaces MUST keep the separator out of account ids, since `a` with `b/c` and `a/b` with `c` spell the same string, and SHOULD choose an id that never changes.

### 9.3 The sort key

`items.sort_key` gives an item's position in its collection's natural order. Annex A defines what a key holds per kind. It is **written, never derived**: the store MUST NOT parse a summary to obtain it. Byte order is the order (`BINARY`), a timestamp being RFC 3339 UTC at fixed width with the `Z` designator; `''` means unknown, last in a descending listing, first in an ascending one; `seq` breaks ties, so a page over `(sort_key, seq)` is total. A write leaves an existing key alone unless it carries a new one. A page over a set of collections is ordered on `(sort_key, seq, collection)`, merging each collection's order: it reads no other collection's rows nor another kind's, and a collection named twice is read once. A wrong key mis-sorts and loses nothing.

## 10. Sync model

A shared item holds the merged truth; a binding per source records the base last agreed with that source, from which the sync part (SYNC.md) derives what changed on each side. A binding records two agreement points and a store MUST keep both:

- `base_object`, what the source last agreed with its remote, moved only by a sync;
- `shared_object`, what it last agreed with the shared item: moved by an absorbed upsert carrying a body and leaving the item unconflicted, never by a pull carrying none (SYNC.md §9), and pinned (§5).

`level` is the tier an item reached, a claim; `items.object IS NOT NULL` is the fact of a body. A remote content change drops the body while the level stays; a release (§11.4) drops both. `deleted` carries a removal until every source has dropped it, and the item is then retained (§11). A member a source lists arrives with its identity and summary (SYNC.md §4) and becomes an item and a binding in the write of the page that lists it.

**Coverage and rounds.** A source syncing a mail collection under a scope lists it in rounds (SYNC.md §5), on its `sources` row:

- the write of a round's first page opens it: `round` raised by one, the round's id, its scope and band recorded in `round_since`, `round_until` and `round_band`, `round_started_at` stamped;
- every page sets `bindings.round` to that id on the bindings of the handles it listed, and records its cursor in `round_cursor` and any checkpoint it carries in `round_checkpoint`; a delta head (SYNC.md §5), in a write of its own, stamps the handles it listed and records its checkpoint, keeping the cursor; a band head records neither;
- the last page reads the members it found absent: the source's based bindings whose `round` is not the round's, under a handle not provisional, whose item's `date` falls in the scope, or is unknown and the round is no band round; a listing a date filter narrowed (SYNC.md §4) proves a member's absence only when an unfiltered enumeration of the collection's handles lacks it, and of none when the round hands no enumeration;
- the write after the last chunk closes the round: `checkpoint` takes the round's checkpoint, the coverage its scope, `covered_at` is stamped, and the round's columns are cleared.

A rebuild closes no round: a rekey lands its checkpoint and leaves the coverage alone. A scope narrowing inside the coverage is recorded with `covered_at` unchanged.

Two divergences are recorded and are not the same fact: `items.conflicted` and `items.conflict_object`, two sources editing the shared body differently; `bindings.conflicted`, `conflict_revision` and `conflict_object`, one source diverging from its own remote. A store MUST persist both independently, and the schema holds that neither carries a diverging body without its flag. A binding's conflict MUST be cleared when the sync writes any resolved state for it, releasing the pin its `conflict_object` held. An item's conflict MUST be cleared, releasing its pin the same way, by the write that adopts a body for it (an `Edit`, SYNC.md §7, or an upsert the collection's policy lets through), or by the upgrade or the write filling, under a `prefer-` policy, the body a divergence was recorded without (SYNC.md §6, §9), whichever body that policy keeps. A write filling an item a pull emptied, under `manual`, leaves the conflict standing.

A write resolving an existing `(collection, link_id, source)` binding to a different handle MUST be refused, recording no trace of the incoming handle. A rebind is licensed only by a drop of the bound handle in the same batch, with reason `Superseded` (a provisional handle an accepted add replaced) or `Rekeyed` (§12). A source holding one identity twice never reaches the refusal: the second copy resolves to a minted key (§9) and is stored beside the first.

A write resolving a bound handle to a different link id, a `hash:` key that changed under the same DAV resource (§9), MUST retire the old binding first, in the same transaction, as a `Deleted` drop of that handle would (§11). The unique index on `(collection, source, handle)` refuses a write that does not.

## 11. Retention

When an item's last binding vanishes the store MUST retain the row rather than delete it. Only an explicit purge removes it, or the owner's eviction below a date (§11.3), so a remote expunge never destroys the local copy.

The one exception is an identity another collection of the same account holds live with the same body (the item moved, or was filed twice): the row is purged in the same transaction. A retiring row holding no body is purged for any live holder, a message only for one that agrees with it (§9).

A retained row carries `deleted = 1`, no bindings, and a non-`NULL` `retained_at`, which the schema holds. When to sweep is the owner's schedule. A tombstone a source still binds, because that source may not remove it (SYNC.md §5), never reaches retention: it stays `deleted = 1` with its binding, hidden from the live reads and listed in the trash.

A body a merge does not adopt (SYNC.md §5, §9), one an overruling `Edit` settles away (SYNC.md §7), or the retained body of a mutable item a bodiless placement revives (§11.1), is retained as an item of its own: inserted beside the item it lost to, under the key minted over the handle of the binding that settled it (§9), holding that body, its summary and a `seq` of its own, retained at once, `retained_by` that binding's source, in the write that settled it.

### 11.1 Requirements

- **Retire, do not delete**: a writer MUST stamp `retained_at` and `retained_by` and keep `object`, so the body stays pinned.
- **A held identity is not kept twice**: when another collection of the same account holds the link id live with the retiring body, or the retiring row has none and, for a message, the holder agrees with it (§9), the retained row is purged in the same transaction, its pins released. A holder of the retiring body is of any kind.
- **Hidden from the sync seam**: what an engine loads to project never includes a retained row, or the next run re-uploads it.
- **Hidden from the reads**: a deleted row MUST be read as a tombstone under §14.1's live-only rule; the trash view lists every deleted row, `retained_at` saying whether a source still binds it.
- **Purge is the only true delete** of a retained row: it deletes retained rows alone, releasing their pins in the same transaction; the bodies fall to the collector. A tombstone a source still binds is not purgeable.
- **A reappearing link id revives**, as §9's table says: `retained_at` and `retained_by` cleared, `deleted` back to 0, `seq` kept, for a source-side resurrection and a queued `add` alike.
- **A revive adopts the incoming body when there is one**, and the retained body it replaces is released, kept apart for no kind. When the incoming placement carries none, for an immutable kind the retained body stays and becomes the binding's base; for a mutable kind the revived item holds no body, at `Meta`, and the retained body is kept as a retained item of its own (§11), keyed over the reviving binding's handle and reported (SYNC.md §5). The pins the retained row held are released only for what the revive replaced.
- `retained_by` is diagnostic; a retained item has no binding and pushes nothing.

### 11.2 Purging

A purge empties one retained item, or every item retired before an RFC 3339 instant the owner computes from its own policy, store-wide, reading the retained rows on `items_by_retained`. Each purged row counts in `store_meta.purges` (§4.5), and a purge removing the last row holding a `seq` takes its properties (§4.3).

### 11.3 Evicting below a date

Nothing in pimdir is deleted by inference: mail older than a source's scope stays stored and readable, and a sync neither drops it nor pushes anything for it (SYNC.md §5). Freeing that space is the owner's, on the user's request, by an **eviction**: every live mail item of a collection whose `date` is older than an RFC 3339 instant and that owes nothing is deleted with its bindings and summary. An item with no `date` is never older. An item owes something, and stays, while it has no binding; it or a binding of it is conflicted, or a binding has no base; a binding of it is a delivered create's (§2); its flags differ from a binding's base flags, both known; a person's reference names it (§14.2); or its `seq` holds a property (§4.3).

An eviction stamps no tombstone, queues nothing and derives no push: the remote keeps every member, which a later widening names again. It MUST run in one transaction with every refcount recounted (§7); the bodies fall to the collector, and each row counts in `store_meta.purges`. It MUST NOT run between two chunks of a verb (§5). An owner SHOULD drain the queue first, an action addressing an evicted item by `seq` being parked. An owner narrowing a scope and evicting below it records the narrower coverage with the next sync, not before.

### 11.4 Releasing bodies below a date

An owner keeping only some mail bodies frees the others by a **release**: every live mail item of a set of collections whose `sort_key` lies below an RFC 3339 instant (or with no ceiling, the undated below any) and that holds a body it does not need goes back to `Meta`, `object` cleared and `level` set to `1`, its summary, flags, bindings and `seq` kept. A binding whose `base_object` or `shared_object` is that body releases it too (§5) and stays based, `base_present` saying so alone (§13), so the body falls to the collector.

An item needs its body while it or a binding of it is conflicted, a binding has no base or holds another body as its base, it has no binding, or a source with a `sources` row on the collection binds it not (SYNC.md §9). An unpushed flag holds no body back.

A released body is fetched again by the next `Full` upgrade (SYNC.md §6); a released row is no claim, a sync naming it at `Meta`. The write releases one body the same way on its own, the bare one of two members stating one hint that would share it (§14). A release stamps no tombstone, queues nothing and derives no push. The bases and the bodies are released in one transaction with every refcount recounted, each released item restamped (§4.5). It MUST NOT run between two chunks of a verb (§5).

### 11.5 Erasing

A purge removes a row from the tables, not its bytes from the files: SQLite leaves freed pages in the file and the WAL, FTS5 keeps a deleted row's tokens until its segments merge, and the collector unlinks a body only once no row names it. Every connection writing pimdir.db or index.db MUST set `PRAGMA secure_delete = ON`. An owner erasing an item, at the user's request, runs in order:

1. its purge (§11.2), or the delete of an item no source binds (§14.3), the pins released in the same transaction;
2. the collector (§5);
3. where an index is kept, the indexer's refresh removing the item's rows from index.db, its full-text segments merged;
4. `PRAGMA wal_checkpoint(TRUNCATE)` on pimdir.db and index.db, until it reports every frame checkpointed.

The item's bytes, its properties among them once no row holds its `seq`, are then in neither database nor in objects/, unless another item names the same body. A backup, quarantine/ and the filesystem's own copies are beyond the store's reach (§18).

## 12. Collection generation

`collections.generation` is the handle-space epoch, from 1, which readers deriving epoch-dependent protocol values read. The owner MUST raise it by one in the transaction of the rebuild that re-learns a collection's handles (an IMAP `UIDVALIDITY` change). Ordinary syncs, full resyncs and content changes MUST NOT raise it. A rebuild's batch drops the old handles with reason `Rekeyed` (§14), which licenses the move and tells the store the batch is a rebuild; a duplicate in the same batch is still refused.

## 13. Encodings

Two implementations produce byte-identical stores only with identical encodings. The schema holds each column's type and bounds; this section says what a value means.

A **closed** vocabulary is held by a `CHECK`: a value outside it is refused at the write, and adding one is a new schema version raising `read_version` (§6). An **open** one is checked by no constraint, so it grows within a version: a reader MUST read a value it does not know as this section says for that column, never as an error. Closed: `kind`, `level`, `marks` and `base_marks`, `deleted`, `conflicted`, `conflict`, `support`, `origin`, `hash_algo`, `summary.component`, and `item_reference.role`, which also takes any `x-` name. Open: `collections.role`, `action`, `capability`, `summary_value.role`, `dtstart_value` and `due_value`. A fifth kind therefore raises `read_version` and locks every earlier reader and producer out of the whole store (§4.2).

- **`kind`**: `message/rfc822`, `text/vcard`, `text/calendar` or `application/octet-stream`; `''` until declared. **`level`**: `1` meta, `2` full. **`conflict`**: `manual`, `prefer-incoming` or `prefer-existing`, a `prefer-` policy keeping the body it does not adopt as a retained item (§11).
- **Flags.** A flag is one raw flag, compared by its bytes, non-empty printable ASCII without a space (`\Seen`, `$label`), as IMAP flags and JMAP keywords are. A set holds each flag once. **`marks`**, **`base_marks`**: the set's system flags, each by its exact bytes, as the sum of its bits: `\Seen` 1, `\Answered` 2, `\Flagged` 4, `\Draft` 8, `\Deleted` 16. **`keywords`**, **`base_keywords`**: every other flag, `\seen` and `$Important` among them, sorted bytewise and joined by one space, `''` for none; the writer sorts them, writes each once and writes no system flag there, the schema holding the shape alone. **`flags_known`**, **`base_flags_known`**: `1` the bits and the keywords are the set, both empty being known-empty; `0` unknown, both empty. A reader reads the set as the flags the bits name followed by the keywords.
- **`link_id`**: the hint verbatim, `esc:` and the hint, a kind fallback, or a minted key (§9); opaque.
- **`sort_key`** (§9.3) is the one column exempt from byte identity: a zoned time resolves through a time zone database two writers may hold at different versions.
- **`changed`**: the stamp of §4.5, `-1` only as a request inside a statement. **`purges`** counts every item purged or evicted, every object collected and every collection renamed or deleted.
- **Summary columns**: Annex A's, `NULL` for absent and unknown unless it says otherwise. A message's `date`, and a scope's `covered_since`, `covered_until`, `round_since` and `round_until`, are an instant at seconds precision with the `Z` designator (`2026-08-01T10:00:00Z`), held so by constraint, or `NULL`, an open bound for a scope. A message is in a scope when `since <= date < until`, or when its `date` is `NULL`.
- **`summary_value`**: `role` an address role of Annex A.6, `in-reply-to` or `category`; `position` the 0-based document order within the role; `value` a canonical address, a bare Message-ID or a category; `name` an address's display name or `NULL`. A reader reads a row whose role it does not know as naming its value in no role it shows, and still answers it where a read asks for any role. A card's telephone has no row (SEARCH.md §6).
- **`dtstart_value`, `due_value`**: `date-time` or `date`; a reader meeting another value does not interpret the time beside it, and orders the item by its `sort_key`.
- **`item_reference`**: `from_kind` and `to_kind` a kind; `role` `attachment`, `invitation`, `sender`, `parent`, `source`, `related` or `x-` and a name; `origin` `auto` or `user` (§14.2).
- **`base_present`**: whether a base exists, the one witness of a base. A binding with no base holds no base flag set, `base_object` nor `base_revision`; a delivered create's base names nothing, `base_present` 1 with the three empty. **`base_revision`**: an opaque etag or modseq.
- **`conflict_revision`, `conflict_object`** (on a binding): the remote revision and body observed when the binding was marked conflicted. A binding that is not conflicted MUST NOT carry either.
- **`server_object_id`**: opaque, comparable only with another binding of the same source in the same account (SYNC.md §6).
- **Stamped instants**, `created_at`, `retained_at`, `applied_at`, `refused_at`, `covered_at`, `round_started_at`: stamped by SQLite as `strftime('%Y-%m-%dT%H:%M:%fZ','now')`, the shape held by constraint (`2026-08-01T10:00:00.000Z`). Every instant the format fixes is UTC with the **`Z` designator**, never `+00:00`.
- **`round`**: on a source the last round id drawn, `0` before any; on a binding the round that last listed its handle. **`round_band`**: `1` while the open round lists only the band its coverage lacks.
- **`refusal`**, **`refused_key`**, **`refused_at`**: the reason the remote gave for refusing a change of this source for good, scrubbed of credentials (§18), that change's idempotency key (SYNC.md §4), and when; all three set or none. A refusal recorded replaces the one standing.
- **`action`**: `add`, `set-flags`, `remove`, `move`, `copy`, `update`, `set-performer`, `set-property` (§15.3), an intent of Annex B.2, or an application's own. **`capability`**: a name of Annex B, or an application's own starting with `x-`.
- **`payload`**: versioned JSON with a leading integer `v` (§15.3). **`target_collection`**: the collection a `move` or a `copy` names as `to`, or one an `add` names in `supersedes`, written by the producer with the payload and read by the owner in place of the payload's. **`error`**: `NULL` while pending, set when parked; free text, but a text beginning with `unconfirmed: ` says the row is an intent whose outcome is unknown (§15.2), and no other row's begins so.
- **`sync_version`**: `sync-vN`, or a draft's `sync-draft-NN` (§14, SYNC.md §10). **`format_version`**: `storage-vN`, or a draft's `storage-draft-NN`, which §4.2 refuses.
- **`store_id`**: 32 lowercase hexadecimal digits, 16 random bytes drawn at creation. **`incarnation`**: 1 at creation, raised by every restore (§8). No program changes `store_id`, and none lowers `incarnation`.

## 14. Operations

A store is opened as one source. The **load** reads the shared items and that source's bindings, which a sync engine projects into placements (SYNC.md §3); the **write** folds the source's changes back as a batch. Both are this part's interface, whoever calls them.

**The load** of a collection under a **selection** reads its items, never a retained one, with their summaries, that source's bindings, checkpoint, coverage and round. The selection is a floor: `All` reads the collection; `Links` the items and bindings under the link ids named, answering who holds each key and never offering a create for an item the source lacks; `Handles` resolves each handle to its binding's link id and reads the same, a handle nothing binds being a member to name, and, in a mail collection, every item under a key minted from a key it reads that a writer does not derive (§9), the other members stating that hint (SYNC.md §6). A delta reads what owes a push without `All` (SYNC.md §10): the source's bindings whose owing mark is set, and the link ids of the items whose lacking mark is set and this source binds not (§4.6). A store MAY return more than the selection names, never a retained item (§11.1), and MUST NOT return less. The load also names the tombstones whose remove is held (§15.3), for each pending create superseding an item of its own identity the binding it may be moved from (SYNC.md §4), and the refusals standing in the collection (SYNC.md §5).

**The body lookup.** Given link ids and a source, the store answers, for each row of the caller's account holding a body under one of the keys, the body's hash and size, the row's subject, `date` and `sender` (`NULL` without a summary), and the `server_object_id` that source's binding on the row states: the witnesses a link is checked against, one per holder (SYNC.md §6). A writer-derived key never matches (§9).

**The batch.** A writer hands the store its changes as a batch: one collection, one source, and a list of operations the store applies in order and atomically, and MUST NOT reorder. A batch names one handle twice to supersede a provisional one, and a rebuild drops every old handle before it upserts any new one. The operations are:

- `UpsertPlacement`: one placement of the source: its handle, its link id when the writer names the member, its flags, object, level, sort key, summary, base and conflict, merged into the shared item and the source's binding (§10).
- `DropPlacement { handle, reason }`: the source's binding of a handle goes. `Deleted`: the member is gone from the source, or is a delivered create given up on request (SYNC.md §7), and the item is marked deleted, retained once no binding is left (§11). `Superseded`: a provisional handle an accepted add, a landed arrival or a relocation replaced. `Rekeyed`: a handle a rebuild renumbered, making the batch a rebuild (§12). The last two license the binding to move to another handle in the same batch and mark nothing deleted.
- `DeliverPlacement { collection, handle }`: the source's create under the provisional `handle` was delivered (SYNC.md §2, §4): a binding holding no base gains one naming nothing. A relocation's names its destination's collection (SYNC.md §5).
- `LandPlacement { collection, handle, to, revision }`: the source's create under the provisional `handle`, pending or delivered, is the member a relocation made under `to` (SYNC.md §4): a `Superseded` drop of `handle` then the binding written under `to`, its base the item's flags and body and `revision`. A binding whose base names a flag set, a revision or a body, or no binding under `handle`, is left as it is; one whose `to` the source already binds in `collection` is recorded delivered.
- `RefusePlacement { collection, handle, key, reason }`, `ClearRefusal { collection, handle }`: the remote refused for good the change keyed `key` the source pushed for its binding under `handle`, giving `reason`, scrubbed first (§18), or accepted a push of it (SYNC.md §4, §5): the binding records the refusal or clears it, after the batch's upserts and drops, in the batch's order; a handle nothing binds records nothing. A drop of the handle takes its refusal.
- `StoreObject { hash, size, bytes? }`: an object row, its blob written first or already streamed to its path (§5).
- `Overrule { handle }`: the next upsert of `handle` settles its conflicts by an engine's or a connector's rule (SYNC.md §7), each diverging body it does not adopt, the binding's then the item's, kept as a retained item (§11). It MUST be refused when a conflict it settles holds no diverging body.
- `Settle { handle }`: the next upsert of `handle` is a person's resolution of the item's conflict (SYNC.md §7): the item takes the upsert's body, or keeps its own when that upsert is a tombstone's, `items.conflicted` cleared and its `conflict_object` released, nothing kept. Only these two tell an upsert from a sync's, which leaves an item's conflict standing (SYNC.md §9).
- `SetCheckpoint { checkpoint }`, `SetCoverage { since, until }`: the source's checkpoint, and a narrower coverage it serves (§10).
- `OpenRound { since, until, band }`, `Stamp { handles }`, `SetRoundCursor { cursor, checkpoint }`, `CloseRound { since, until, checkpoint }`: a round's (§10), `OpenRound` first in its batch, `Stamp` after the upserts of its handles, `CloseRound` last; a `SetRoundCursor` naming no cursor keeps the one recorded.

**The write** applies one batch as one transaction. Each named placement writes its item and binding, the system flags in `marks` and `base_marks` and the others in `keywords` and `base_keywords` (§13), and its `summary` and `summary_value` rows, derived by the writer under Annex A and replaced whole. A handle bound to another link id retires that binding first (§10); an item the result no longer holds is retained (§11), and purged at once when its identity is held elsewhere (§11.1). Every refcount the batch moved is settled in its transaction, by the net change or by a recount (§7); a batch that stored or dropped no object MAY skip this. A row created implicitly for the collection takes kind `''` and its id as `name`.

**What a batch may not do.** A placement is always named: an upsert for a handle nothing binds and carrying no link id MUST be refused, and an unlinked one for a handle a binding holds folds into that binding's item. An upsert resolving a binding to a different handle MUST be refused unless a `Superseded` or `Rekeyed` drop of the bound handle precedes it in the batch, and one resolving a bound handle to a different link id retires the old binding first (§10). An upsert naming a mail member by its bare hint is keyed by §9's table against every row the collection holds under that key, whatever the writer saw: a row holding a message the member does not agree with gives the upsert the key minted over its handle.

**A body two members stating one hint would share.** In a mail collection, a batch giving an item under a key minted from a hint (§9) a body it did not hold, the body a live item under the bare hint holds, releases that body from the bare one in its transaction as §11.4 releases one: `object` cleared and `level` 1, its summary, flags, bindings and `seq` kept, and each binding's `base_object` and `shared_object` naming that body let go, the binding staying based. It does not when the batch upserts the bare one, the bare one needs its body (§11.4), a source states one `server_object_id` on its bindings of both, or another live item minted from the hint held that body before the batch (SYNC.md §6).

**Chunks.** A writer MAY cut one operation's writes into several batches, its **chunks**, each committed apart (an engine pushing in bounded chunks, SYNC.md §5).

**The version of the sync state.** The rows an engine writes (`bindings`, `sources`, and `deleted`, `conflicted` and `conflict_object` of `items`) follow the sync part their engine implements, which `store_meta.sync_version` names: `NULL` until an engine writes, then its version, written in the transaction of its first write and whenever another version takes the store over (SYNC.md §10).

**Collections.** A collection's `kind` is declared, never derived, and declaring a collection never overwrites a kind already set. A source offering a collection of another media type has it recorded with no kind and never synced. `name` is a label, never an address: a reader renders `name` and addresses by `id`, and keeping it current is the owner's.

`role` says what the source states the collection is for, `NULL` when it states nothing: for `message/rfc822` the JMAP `Mailbox/role` vocabulary (RFC 8621 §2: the IANA IMAP Mailbox Name Attributes, lowercased, plus `inbox`); for `text/calendar` and `text/vcard` `default`, the collection the source writes to when none is named; for `application/octet-stream` `attachments` (§14.3). A reader MUST read a role it does not know, or one of another kind's vocabulary, as none. An account holds each role of a kind at most once, setting it taking it from the collection that held it (`collections_role_moves`). The owner writes a role only on a declared collection and only from what a source states, never from a name, and clears it when the source stops stating it, `attachments` excepted. With several sources on one collection, the first that states a role, a name or a presentation wins.

`parent` places a collection in its account's hierarchy, `NULL` at the top, from what a source states. The hierarchy MUST stay a forest within an account: a parent is a collection of the same account, never the collection itself nor one under it, and the owner writes no parent that breaks this or that the store does not hold. `color`, `description` and `sort_order` are what the source states, read as untrusted text (§18).

A source's **capabilities** are declared as a set, its rows deleted then written in one transaction (§15.6). A **performer** row is written or deleted applying a `set-performer` (§15.3).

**Renaming a collection** is an update of `collections.id`: every foreign key onto it and `bindings`' key onto `items(id, collection)` cascade, and the items are restamped under the new id (§4.5). `queue.target_collection`, which no key cascades, follows the rename in the same transaction; the payload keeps the id it was enqueued with, but for a `submit`'s `copy` (Annex B.2), the one collection a payload names that no column holds: the rename rewrites it in the same transaction on every queued `submit` naming the old id, pending or parked, since its performer files the copy where the payload says once the message is sent (§15.5), a send it could not file being one it cannot repeat. An account rename renames each of its collections and their `account` in one transaction, its capabilities and performers written again.

**Deleting a collection** cascades to everything under it, retention not applying; a receipt of a row queued on it names no collection after (§15.4), and the delete counts in `store_meta.purges` (§4.5). A collection holding a pending or parked action is refused (`queue.collection` is `ON DELETE RESTRICT`): the operator cancels each row (§15.5) or lets the drain apply it first. Every refcount MUST be recounted in the same transaction, unless the collection held no pointer at an object.

### 14.1 Reading the store

A **reader** (§8) opens read-only and projects the store, keyed by `seq`. A collection is listed with the narrowest of its sources' coverages (the latest `covered_since`, the earliest `covered_until`, the oldest `covered_at`), and none while one of them has never closed a round. Three rules bind every read:

- **Live only.** A tombstone (`deleted = 1`) is never presented as live; the trash reads present their rows as deleted.
- **Level-aware.** `level` says the tier reached, `object` whether a body is there. An absent body, or a blob gone under a purge, is not yet hydrated, never an error.
- **Snapshot-consistent.** A reader sees a WAL snapshot and runs beside the owner. It detects change by `PRAGMA data_version` or the feed (§4.5), and overlays the queue as §15.4 says.

### 14.2 References

A **reference** says that one item bears on another (a message and the file it attaches, an invitation and its event, a mail and its sender's contact, two things a person linked), a fact recorded once, never recomputed. Nothing requires one: an owner MAY record references and a reader MAY ignore them.

- An endpoint is a collection kind and a `link_id`, never a collection, so a move keeps a reference. A writer-derived key (§9), or a `part:` key over one, is no endpoint, and the schema refuses it.
- `origin` is `auto`, recorded by a writer's rule, or `user`, by a person.
- A reference is recorded only between two endpoints each holding a row of `items` in a collection of its kind, never from an item to itself. Recording it again changes nothing, save that `user` takes over `auto`. A reference is removed whatever its origin; no suppression is kept.
- A reference goes with the last row of either endpoint (`items_drop_references`), live, tombstoned or retained; a move, a tombstone, a retention and the loss of one copy among several keep it.
- A reference stamps nothing (§4.5), and no source learns of it.

**Automatic references.** An owner MAY record references by rule; one that applies a rule below MUST record what that rule states, so two owners over one store record the same. A rule's reference runs from the item whose content states it to the item it names, origin `auto`, both ends live when recorded, and never alters one already recorded. It runs after the write that changed what it reads at either end, in that transaction or the next; run over every item, it backfills a store.

- **`sender`**: a mail to every contact whose `email` rows hold one of the mail's `from` values (Annex A.6). An address removed removes nothing.
- **`invitation`**: a mail to the calendar item whose link id its `invitation` names (Annex A.1).
- **`attachment`**: a mail to the stand-ins of its parts (§14.3).
- **`parent`**: a task to the calendar item whose link id its `parent` names (Annex A.4), never itself.
- **`source`**: a task to the mail whose link id its `mid` names (Annex A.4).

### 14.3 Files

A **file** is an item of a collection of kind `application/octet-stream`, a **folder**. Its name and media type are its summary's (Annex A.7), so a rename is a summary write and one file in two folders two rows sharing a `link_id`, a `seq` and a body. A file is mutable: an edit, a push gated on the base and a divergence follow the content axis as a card does (SYNC.md §5).

**A collection no source syncs** holds items no binding names: a folder on the device, the attachments collection below, or a local calendar collection (`text/calendar`) a person keeps on the device. The owner writes their items and summaries directly; §11's retention does not apply, and no projection offers them. An id beginning with `U+0001` is one no server gives. Deleting such an item releases its pins in the same transaction; a bound item is its source's to remove.

**An attachment** is a file inside a message's body, stood for by a file holding no body: `object` `NULL`, `level` `1`, its summary naming the part (`part`, the IMAP section of RFC 3501 §6.4.5), keyed `part:` (Annex A.7). A part is stood for exactly when it makes the attachment mark (Annex A.1), at most the first 1,000 per message in the walk's order; a reader finding 1,000 reads the rest from the message's body. A message under a writer-derived key gets none (§9).

Stand-ins live in the account's file collection holding the role `attachments`, which no source syncs, declared by the owner, named `attachments`, when the account has none. That collection's id MUST be the account, `/`, `U+0001` and `attachments` (`work/\u0001attachments`), or `U+0001` and `attachments` alone for collections under no account (§9.2), so two owners of one store declare the same. An `attachment` reference from the message (§14.2) ties them, and the owner MUST record the file and that reference in one transaction. A `Meta` stand-in claims nothing (SYNC.md §6): a reader opens the part from the message's body, or has its source fetch the part.

An owner recording attachments records a message's stand-ins in the transaction that stores its body, whatever stores it, when the body **enters**: when no row of its key in the account held it before. A move, a copy, a second label or a body released (§11.4) then fetched again records nothing, and a body held before is never walked: a stand-in is never backfilled nor recomputed. A body entering under a key another row of the account holds another body under, a message it does not agree with (§9), records no stand-in and no reference.

Saving an attachment places the same `link_id` in a folder with its own body, the stand-in staying. A stand-in goes once no reference names it (`item_reference_collects_files`): a file holding a body, or one a source syncs, is never collected so.

## 15. Action queue

Only the owner mutates (§8), yet other processes originate mutations: a **producer** appends an action to `queue`, the **owner** applies it. Actions address collections and public ids; intents (Annex B.2) carry what is not a store mutation. What a source supports is declared beside the queue (§15.6).

### 15.1 Producing

A producer enqueues in one transaction: the collection's row, created with kind `''` when absent; when the payload names a body, its object row, after its blob (§5), and its pin; then the queue row, its `object` the body's `id`, the payload's `object` restating the hash. `created_at` is stamped by SQLite, and the row's `id` is the handle the producer follows it by (§15.4). This is the only write a non-owner may perform, and when the owner applies it is the owner's.

A producer MAY enqueue several actions in one transaction, each on the terms above, its body stored and pinned before its row: all of them are appended or none, in the order enqueued, which their ids keep. It holds the staging lock across them all (§8).

### 15.2 Applying

The owner drains the pending rows (`error` `NULL`) store-wide in ascending `id`. An action is applied and its row deleted in one transaction, which spans no network I/O, the row deleted first: a delete that removes nothing means the row is gone, cancelled or applied by another handle, and not this transaction's to apply. That transaction writes the row's receipt: its `id`, its collection and the `seq` of the item it acted on, the item a `set-flags`, a `set-property`, an `update` or a `remove` names when the store holds it, the item an `add` created, the one a `move` or a `copy` left in its target.

A `set-property` runs as no source (§15.3). Any other action against an existing item runs as a source binding it, an `update` or a `remove` stating `resolves` as one whose conflict it names; an `add` runs as a source syncing the collection (a `sources` row or a binding there), the owner's own where it is among them. A `move` or a `copy` stages its target's create under the source it runs as where that source syncs the target, else under the one an `add` into the target runs as, in the transaction of the move's tombstone (SYNC.md §7).

**A run of actions in one transaction.** An owner MAY apply a bounded run of pending actions in one transaction, in ascending `id`, each under a savepoint of its own: the savepoint opens, the row is deleted first in it, the action is applied, its receipt written, and the savepoint released. Every action of a run is applied exactly once or not at all.

A failed apply MUST be rolled back before anything else, which restores the deleted row and undoes whatever the apply wrote: its transaction, or in a run its savepoint alone. The park or the retry is recorded only after that rollback, outside what was rolled back.

A failed action is retried, `attempts` raised, a bounded number of times the owner chooses, then parked: `attempts` raised and `error` set, never silently deleted. A failure of the store itself (a refused rebind, a constraint, a target collection with no declared kind) is permanent for the row and MUST park it. Only a failure of the environment (the database busy, a body unreadable) is retried, and neither MUST stop the rows behind it. An `add` or an `update` whose body cannot be read (its blob missing, failing to read or failing its name, §7) MUST be retried, then parked once the owner's bound on attempts is reached. It MUST NOT be applied without its body.

**An intent whose outcome is unknown.** A performer that sent an intent's request and cannot tell whether it took effect (a submission whose connection dropped once the message was handed over) MUST park the row with an `error` beginning with the reserved prefix `unconfirmed: `, the text after it free, the attempt counted, the owner writing the prefix before the detail. It MUST NOT perform it again of its own accord: the effect may be made, and a second one is not undone. An action the owner applies itself never ends so. A park whose failure text begins with the prefix writes `failed: ` before it. A parked row is listed by no drain, and leaves that state only acknowledged by its performer, retried on a person's request, or withdrawn (§15.5).

**Skipping is not parking.** An owner that does not recognise an action, does not know the payload version `v` a row states for an action it knows, or does not run the source an intent names, MUST leave the row pending and untouched (`error` `NULL`, `attempts` unchanged) and MUST NOT block later actions on it. A capability a declared source does not support parks the row (§15.6). A drain has three outcomes per row: applied, parked, skipped.

### 15.3 Actions

Existing items are addressed by `seq`. A payload is a JSON object, typed by the JSON Schema (2020-12) of its action and version, payloads/<action>.v<v>.schema.json, which binds. The shapes below and in Annex B.2 restate them: `n` an integer from 1, `hash` an object name (§5), `key`, `id`, `collection`, `addr` and `label` a non-empty string, `text` any string, `[…]` a flag set as distinct flags (§13), `[addr…]` a non-empty array of `addr`, `[hash…]` a non-empty array of distinct `hash`, `property` a property's key (§4.3), `pimdir/label` or one outside `pimdir/`, `[value…]` 1 to 64 distinct property values (§4.3), a quoted value the member's one value and quoted values joined by `|` its choices, `?` an optional member, `( a | b )` exactly one of two members, and `( a / b )` one or both of two.

**A payload is valid whole, malformed or unknown.** A payload whose action and `v` an implementation knows is typed by their schema: one missing a member its schema requires, stating one of another type, or holding a member its version does not define is malformed: a producer MUST NOT enqueue it, and an owner knowing its action and version MUST park it, an intent's performer likewise, never applying it in part nor ignoring a member. One whose action, an application's own (`x-`) included, or whose `v` for a known action, it does not know is **unknown** to it: an owner skips it (§15.2) and a reader lists it (§15.4). A payload of a known action stating no `v`, or a `v` that is no integer as JSON writes one (RFC 8259 §6: not `1.0` nor `1e0`, which a JSON Schema validator reads as 1), is malformed and parked. A payload changing shape takes the next `v`; while this part is a draft, a shape at its `v` is edited in place (§4.2). vectors/payloads.json holds payloads of every action. At `v: 1`:

- **`add`**: `{ "v": 1, "link_id": key?, "flags": […], "object": hash, "supersedes": { "collection": collection, "seq": n }? }`. Creates an item staged as a local creation to push under its provisional handle (§2), its summary derived from `object` (Annex A).

  A stated `link_id` is a key §9 assigns; a producer stating none checks the duplicate under the key the owner derives. One beginning with `hash:` names bytes (§9): it MUST be the one the object's own bytes give (Annex A.2, A.3). A producer MUST refuse an `add` stating a `hash:` key another body gives, read from the body it stores before anything is appended, and an owner MUST park one (§15.2). Only a `hash:` key is checked against the body: a stated `alt:` key, read from decoded header fields rather than the bytes, is applied as stated. A live item under the key parks the action; a retained row or a tombstone still propagating under it revives (§11), unless it holds a message that does not agree, when the add is minted (§9's table).

  With `supersedes` the add replaces the item it names (a task filed into another collection): in one transaction the owner applies the add, tombstones the superseded item as a `remove` would, and records the pair in `supersessions`, the duplicate check reading the store before the tombstone. A superseded item already absent is no failure; one no source binds is retained at once. A malformed `supersedes` parks the action. The tombstone's remove is **held** while the item the add created is live and a pending create of a source syncing its collection: no source pushes the delete (SYNC.md §5). A superseding item keeping the superseded item's identity names the binding it may be moved from (SYNC.md §4).
- **`set-flags`**: `{ "v": 1, "seq": n, "flags": […], "base": […]? }`. Without `base` it replaces the set by `flags`, as a producer writing a set it never read does. `base` is the set the producer read and changed into `flags`: the owner adds to the set the item holds each flag `flags` holds and `base` lacks, and removes each flag `base` holds and `flags` lacks, every other flag left as it stands. A producer changing a set it read SHOULD state it. A row stating `base` and meeting an item whose flag set is unknown (`flags_known` 0) MUST be parked: there is no set to add to nor remove from, and replacing would write the unread flags as removed.
- **`remove`**: `{ "v": 1, "seq": n, "if_match": hash?, "resolves": [hash…]? }`. Tombstones the shared item, every source binding it pushing the delete (SYNC.md §9); already absent is success.

  `if_match` is the body the producer read and deletes: when the item's current body is another, or the item holds none, the owner MUST park the row, naming both. A producer deleting a mutable item it read SHOULD state it; a row without it removes whatever the item holds. `resolves` makes the remove a person's resolution of a conflict by deleting. A remove meeting a conflict, the item's or that of the binding it runs through, MUST be parked, naming the conflict, unless `resolves` names the `conflict_object` of each conflict it meets; one stating `resolves` and meeting none MUST be parked. A producer MUST NOT state `resolves` on any other remove.
- **`move`**, **`copy`**: `{ "v": 1, "seq": n, "to": collection }`, a `copy` being a `move` without the removal. The producer writes `to` as `target_collection` too, which the owner reads (§13). A target the store does not declare, or of another kind, parks the action. A `move` whose target is the collection the item is in MUST be parked, naming it, and a producer MUST NOT enqueue one: it would tombstone the item and stage a create beside it (SYNC.md §7). A `copy` there is a second copy, minted. A `move` meeting a conflict, the item's or that of the binding it runs through, MUST be parked, naming the conflict: it states no `resolves`, and the diverging body would stay pinned under a tombstone nobody is shown. A `copy` meets none. Either into a collection no source syncs (§14.3) MUST be parked, naming it: there is no source to stage its create under (SYNC.md §7).
- **`update`**: `{ "v": 1, "seq": n, "object": hash, "if_match": hash?, "resolves": [hash…]? }`. Repoints a mutable item's body, its summary derived again.

  `if_match` is the body the producer read and replaced. When the item's current body is another, or the item holds none (a pull having emptied it, SYNC.md §5), the owner MUST park the row, naming both: applying it would drop another write without a merge (SYNC.md §7). A producer editing a body it read SHOULD state it; a row without it applies over whatever the item holds. `resolves` makes the update a person's resolution of a conflict, naming the `conflict_object` of each conflict the producer showed. A producer deciding a conflict (a resolution command or form) states it, and MUST NOT state it on any other update. An update meets a conflict when the item or the binding it runs through is conflicted. One meeting a conflict MUST be parked, naming the conflict, unless `resolves` names the `conflict_object` of each conflict it meets; one stating `resolves` and meeting none MUST be parked. A `conflict_object` `NULL` is named by no resolution. A resolution applied settles what it meets as SYNC.md §7 settles a person's `Edit`.
- **`set-performer`**: `{ "v": 1, "capability": capability, "source": id? }`. Records `source` as the performer of an intent capability for the account of the collection the action is queued on, or withdraws the choice when `source` is absent (§15.6). A `source` not declaring the capability parks the action.
- **`set-property`**: `{ "v": 1, "seq": n, "key": property, ( "add": [value…] / "remove": [value…] ) }`. Changes the item's properties under one key (§4.3), to the store alone: it runs as no source, needs no capability and derives no push (SYNC.md §3). The item is the one a live row of the row's collection holds under `seq`; none parks the row. The owner deletes each value `remove` names that the item holds, then inserts each value `add` names, in order: a value both name is held after. Under `pimdir/label` values compare folded: an added value whose fold equals one held, or added before it, adds nothing, and a removed value removes the one held of equal fold. An add leaving more than 64 values under the key parks the row. A value past 1,024 bytes of UTF-8, which the schema's `maxLength` counts in characters, or one no UTF-8 encodes (a lone surrogate), is malformed. A key under `pimdir/` other than `pimdir/label` is malformed by the schema: a producer MUST NOT enqueue one, and an owner writes none (§4.3).

**The body is the column's.** An action carrying a body (an `add`, an `update`, an intent such as `submit`) names it in `queue.object`, and an `add` or an `update` restates its hash as the payload's `object`. The owner reads the body from the column and never builds a path from the payload: a row whose payload's `object` is not the hash the column names, the column `NULL` included, MUST be parked, naming both.

**An item no source binds** is the store's alone to settle: an owner MUST apply or park an action naming it, never skip it. A `remove` retains it (§11). In a collection no source syncs (§14.3), a `set-flags` and an `update` apply to it directly on the terms above, a body deriving no key or another parking the row, and a `move` or a `copy` parks, a producer filing it elsewhere with an `add` superseding it. A `set-property` applies to it as to any item. In a collection a source syncs, any other action parks: the item awaits its first push (SYNC.md §3).

The intents of Annex B.2 are actions of their own, versioned the same way. An application MAY carry further ones; the store owes them append order, blob pinning and the skip rule.

### 15.4 Reading the queue

A reader MAY overlay a collection's pending actions for read-your-writes. An overlay SHOULD fold a row as the owner would apply it to the rows the reader sees: a `set-flags` stating `base` as the change it is, over the set the item shows; a `set-property` as the change it is, over the properties the item shows, its removes then its adds, a label compared folded; and nothing for a row the owner would park (§15.2, §15.3, §15.6), among them a `set-flags` stating `base` over an unknown set, a `set-property` naming a `seq` no live row of its collection holds or leaving more than 64 values under its key, an `update` or a `remove` whose `if_match` names another body than the item shows, the item showing none included, or one meeting a conflict its `resolves` does not name, a `move` meeting a conflict or into the collection its item is in, and an action on an item no source binds that §15.3 parks. An overlay is a prediction: a producer gating a write on it states `base` or `if_match`, which the owner checks again.

An overlay also holds what other collections' pending `move` and `copy` rows bring into the collection, by their `target_collection`. A pending `add` shows in no listing of items, the `seq` of what it creates being the owner's to draw (§9.1): a reader shows it apart. A row whose action, or whose `v`, the reader does not know is folded into nothing and still listed as pending, with its action and its `created_at`.

A producer follows one row by the `id` its enqueue answered, under the store id and incarnation it recorded (§4.5): pending while `error` is `NULL`, parked otherwise, of unknown outcome when `error` begins with `unconfirmed: ` (§15.2); once gone, its receipt says it was applied and which item it acted on, so a producer learns the `seq` of what it staged.

**A refused push.** A source's remote may refuse an applied row's change for good (SYNC.md §4), the refusal standing on the binding of the item (SYNC.md §5): a producer reads, beside the receipt, the refusals standing on the rows holding the receipt's `seq` in the account of its collection, and shows the row applied and refused. The row is not parked again; the way out is an action on the item, a `remove` withdrawing a refused create (SYNC.md §7). The refusal is cleared by that source's next accepted push, and goes with its binding.

A row found in neither the queue nor the receipts was withdrawn, or applied longer ago than its receipt is kept: the owner keeps a receipt at least seven days after `applied_at`, and while a refusal stands on its item, then MAY drop it.

### 15.5 Cancelling and acknowledging

**Cancelling** deletes a pending or parked row: an operator withdrawing it, or the performer of an intent acknowledging it. It is an owner write, the row deleted and its pin released in one transaction. An applied action cannot be cancelled.

A performer acknowledging an intent it performed MUST record the intent's receipt in that same transaction: its `id`, the collection it was queued on and, as `seq`, the item its effect left in the store when the performer knows it, `NULL` otherwise (a collection created, a message sent). A withdrawal records none, which is how a producer tells the two apart. An intent that failed is parked or left pending, never acknowledged.

**Retrying** puts a parked row back among the pending ones, on a person's request and never of the owner's own accord: `error` cleared, `id` and `attempts` kept. It is the one way an intent parked `unconfirmed: ` is performed again. An intent whose effect is not a store mutation is therefore at-least-once, and deduplicating is the performer's.

An intent that leaves a store change behind, the copy of a sent message, is acknowledged by replacing it: in one transaction the performer enqueues that change as an ordinary action, its body pinned, cancels the intent and records its receipt with a `NULL` `seq`.

### 15.6 Capabilities

The owner declares what each source can do and parks an action no source concerned can carry out (the owner's backstop); a producer reading the same rows before it enqueues (the producer's gate) shows the gap at the action.

**Declaring.** The owner declares every source it runs, under the account the source syncs for, as a set (§14), before it drains an action for that source and whenever the source's configuration changes. A row names a capability of Annex B, or an `x-` one, with `support` `full`, `partial` or `none`, the `detail` saying what is missing or why. A declaration MUST write every capability of Annex B's base set the owner knows of the kinds the source syncs, `none` included, so a source supporting nothing still says so; a right its configuration withholds (SYNC.md §5) is `none`. A row with no `collection` holds for the whole source; one naming a collection overrides it there (a calendar shared read-only). A source with a row is **declared**, and a base-set capability it has no row for, or a `none` row, is unsupported; a source with none is **undeclared**, gated by nothing. A capability Annex B adds after its base set is read only where a row states it.

**The sources concerned** an action's capabilities (Annex B) are read against: for an action on one item, every source binding it, but for a `remove`, a `move` or a `copy` not one binding it as a pending create alone (SYNC.md §7); for an `add`, every source syncing the collection; for a `move` or `copy`, also every source syncing the target that binds nothing of the item, or only a pending create, asked what an `add` of the item needs there; for an `add` carrying `supersedes`, also what a `remove` of the superseded item needs.

**The producer's gate.** Before it enqueues, a producer SHOULD resolve the capabilities the action needs against the sources concerned, and enqueues no action a declared source does not support, reporting the capability, the source and its detail. A `partial` support passes and its detail SHOULD be shown.

**Components.** `calendar.component.vtodo` `none`, on a collection or source-wide, says a calendar takes no VTODO resource (RFC 4791 §5.2.3), `full` that it does, read only where a row states it, for an `add` or `update` whose new resource is a VTODO and for a `move` or `copy` of one, in the collection it lands in.

**Implementations.** A source declares one implementation per capability, which the `detail` names when it matters (`by iMIP`). Several for one account are several sources; an owner holding two for one source exposes them as two or picks one, the only way for a state capability. An implementation reaching only what its source holds declares the capability on those collections and `none` source-wide.

**Intents.** An intent (Annex B.2) is performed by exactly one source, its payload's `source`. Its candidates are the sources of the account of the collection it is anchored on whose row there (the collection's, else the source-wide one) has some support. An intent addressing an item is anchored on the item's collection; one creating a collection on the parent it names, else on a collection of the account and kind the new one takes; one renaming or deleting a collection on that collection. No candidate is a refusal; one is the performer; with several, the user's choice while still a candidate: the latest `set-performer` queued for the account and capability, else the `performers` row. Otherwise the producer MUST NOT choose: it refuses, listing the candidates, and the user picks, for this action alone or durably through `set-performer` (§15.3).

**The owner's backstop** is authoritative. An action reaching the drain needing a capability (Annex B, `calendar.component.vtodo` included) that a declared source concerned does not support, or an intent whose `source` does not declare its capability, MUST be parked with the capability and the source named in `error`.

## 16. Test vectors

A body named differently, a summary derived differently or a key sorted differently fails nowhere, so vectors/ is part of the format:

- **vectors/objects.json**: bodies to their BLAKE3 digests, names and paths (§5), and the RFC 4648 §10 base32 vectors.
- **vectors/summaries.json** and **vectors/fixtures/**: bodies to the `link_id`, the summary row and its values and the `sort_key` Annex A produces, a message's stand-ins (Annex A.7), and the `alt:`, `hash:`, escaped and minted keys of §9.
- **vectors/payloads.json**: queue payloads of every action, valid, malformed or unknown against payloads/ (§15.3).
- **vectors/versions.json**: format versions ordered by §4.2.
- vectors/sync/ and vectors/search/ belong to the other parts; the feed each step of vectors/search/refresh.json leaves (`changed`) binds an owner all the same (§4.5).

§17 binds them by profile. A summary vector states a row as the model holds it, its lists (`in_reply_to`, `categories`) as arrays though the store keeps them as `summary_value` rows, and a consumer MUST compare parsed structures, never JSON text. The values are authored from the prose, never from an implementation. checks/schema.sh holds the schema to its rules (§4.1, §4.4), checks/floor.sh loads it on SQLite 3.18, and checks/rehearsal/ runs the migrations §6 foresees on a populated store.

Every file under vectors/ states the version of its format as a top-level `v` and conforms to the JSON Schema of that format under vectors/schema/, which checks/vectors.py validates; an implementation meeting a `v` it does not know MUST NOT read the file as a version it knows. An implementation that vendors vectors/ SHOULD record their digests and re-check them against this repository in its CI.

## 17. Conformance

An implementation conforms to this part by one profile, each holding the one before. It MUST meet every section its row names and pass the vectors its row names, and MUST state its conformance as each part's version and the profile it meets there, the layers' by SYNC.md §12 and SEARCH.md §12: `storage-v1.0.0 owner, sync-v1.0.0 engine`.

| Profile | What it does | Owes | Vectors |
| --- | --- | --- | --- |
| reader | opens the store read-only and lists it, holding no lock | §3, §4 (a busy timeout, §4.2's refusals), §6 step 2, §7, §8, §9, §11.1's reads, §12's read, §13, §14's reads of a collection's kind, account, name and role, §14.1 to §14.3's reads, §15.4, §18 | objects.json, versions.json |
| producer | a reader that enqueues actions, under the staging lock | the reader's, §5, §15.1, §15.3, §15.6's gate and performer, Annex B | objects.json, versions.json, payloads.json |
| owner | the one process that mutates the store | every section and both annexes | objects.json, versions.json, payloads.json, summaries.json for each summary kind it writes, the feed each step of search/refresh.json leaves (`changed`, §4.5) |

An engine (SYNC.md §12) is an owner. An indexer and a query client (SEARCH.md §12) are readers, a query client tagging a hit a producer.

## 18. Security considerations

A store holds a person's mail, contacts and calendars. Beside the rules bounding hostile content where they are stated (§5, §7, Annex A.1, §14.3, SEARCH.md §7, §8.3):

- **Modes.** A program creating a store MUST create its directory, objects/, its shard directories and quarantine/ with mode `0700` and every file in them `0600`, index.db, the lock files and SQLite's `-wal` and `-shm` included, as an owner creates local/ and what it keeps there (§3), or on Windows with an ACL granting its own user alone. A program opening a store whose directory or pimdir.db another user can read or write SHOULD refuse it, or open it only once the user confirms.
- **Write access is the trust boundary.** A process that can write pimdir.db can write any row: every producer is trusted as the owner is, and the queue is no boundary. An owner MAY ask the user before it performs an intent another process queued (a message sent, an invitation answered).
- **Read access can block.** A process able to read the store directory can hold a lock and stop the owner, which the modes prevent. A lock file MUST be opened without following a symbolic link (`O_NOFOLLOW`, `FILE_FLAG_OPEN_REPARSE_POINT` on Windows), a link there failing the open and naming the store.
- **Names are untrusted.** A file's name, an attachment's `filename`, a collection's name and a part's section come from content or a server, a property's value from any producer, and the store keeps them as stated. A program deriving a filesystem path from one, saving an attachment or mirroring a folder, MUST neutralise in it every path separator (`/`, and `\` where the platform reads one), a `.` or `..` component, NUL, every control character (U+0001 to U+001F, U+007F to U+009F) and every bidirectional formatting character (U+061C, U+200E, U+200F, U+202A to U+202E, U+2066 to U+2069), and MUST NOT write outside the directory it chose.
- **Instructions are not content.** A property `X-PIMDIR-` names (Annex B.1's `X-PIMDIR-ONLINE-MEETING`) instructs a performer. A producer enqueuing an `add` or an `update` of a resource the user did not write as it stands (an invitation added to a calendar, an imported file, a resource copied from a message) MUST first remove every such property from it, writing one only as the user asks.
- **No credential in the store.** No program writes a password, a token, a cookie or any other credential into a column of the store or of the index, the opaque ones included (`checkpoint`, `round_cursor`, `round_checkpoint`, `queue.producer`, `queue.error`, `capabilities.detail`, `retained_by`, `bindings.refusal`, a property's value, `pimdir/session-key` included until a version of this part defines it), and text it records from an error or a remote's refusal MUST first be scrubbed of the credentials it may carry (a URL's userinfo, an `Authorization` header, a token in a query string).
- **A store from elsewhere.** A crafted pimdir.db or index.db can carry triggers and views that run with the opening program's functions. A program opening a store it did not create SHOULD open both with `PRAGMA trusted_schema = OFF` and `SQLITE_DBCONFIG_DEFENSIVE`, which the store schema runs under, each where its SQLite offers it (the pragma from 3.31, the flag from 3.26). Below 3.31, the 3.18 floor of §4.1 among them, such a program SHOULD instead read `sqlite_master` before any other statement and refuse the store when it holds a trigger or a view whose text the schema at the store's version does not create, naming it, and SHOULD register no SQL function with a side effect on the connection. That comparison is made against a version the program knows alone, so below 3.31 a reader or a producer SHOULD refuse a store above its version (§4.2) it did not create, or open it only once the user confirms.
- **Copies and erasure.** A backup holds what the store holds, quarantine/ included, and takes the store's modes. §11.5's erasure reaches no backup, no filesystem snapshot and not quarantine/, which only the user empties (§7).

## Annex A. Summaries (normative)

What a writer derives from an item before its row reaches the store: the identity hint §9 keys on, the item's `summary` row, its `summary_value` rows and its `sort_key` (§9.3). The store parses no body; the schema fixes the columns and vectors/summaries.json the values. A summary holds what a list row shows, sorts by and the store's references read (§14.2); a question about an item's content is the search part's (SEARCH.md).

This annex is at **revision 3**. A change to what a writer derives bumps it, in a minor version of this part, and says which columns it changed; `store_meta.derivation` records the revision a store's rows stand under (§6). Revision 3 changed what a message's header fields give (`uid`, `title`, `sender`, `sender_name`, `date`, its address and `in-reply-to` rows, its `sort_key`), a zoned time a transition skips (A.3), and bounded the walk of a message's parts (A.1). A link id is never re-derived (SYNC.md §6).

A derivation is made from the body, or from a server-side summary (an IMAP `ENVELOPE`, a Graph `$select`, Gmail's metadata, a JMAP `Email/get`) where the kind has a cheap tier. A value such a summary serves raw, as the content carries it, is derived by this annex's rules and MUST then agree with the body's derivation byte for byte, the attachment mark, the size and the invitation aside. A value a server decodes or parses by rules of its own is no derivation of this annex: it stands until the body is read, which replaces it.

### A.0 Common rules

- An item's `summary` row states its `component`: `mail`, `contact`, `event`, `task`, `journal` or `file`. `uid` is the identity the content states and `title` what a list names the item by; every other column belongs to the components the sections below give it, `NULL` on a row of another.
- **Decoded**: RFC 2047 words and RFC 2231 parameters decoded, vCard and iCalendar text unescaped (RFC 6350 §3.4, RFC 5545 §3.3.11), lines unfolded; a message's header fields as A.1 reads them. A property splits on the first unquoted colon (RFC 6350 §3.3). **Verbatim**: the value bytes as the body carries them, unfolded.
- Bytes that are not well-formed UTF-8 are replaced, never refused: each maximal subpart of an ill-formed sequence becomes one U+FFFD, the practice of Unicode §3.9 that the WHATWG Encoding Standard's UTF-8 decoder follows. `caf` and the byte `E9` read `caf�`; `F0 9F 98` before a space, a truncated sequence, one `�`; `C0 AF` and `ED A0 80`, an overlong form and a surrogate, one `�` a byte.
- A `NOT NULL` column is `''` when the property is absent; every other column is `NULL` when absent or not examined, unless the kind says otherwise. An instant is RFC 3339 UTC at seconds precision with the `Z` designator. A list is `summary_value` rows of one role, `position` from 0 in document order, none when absent.

### A.1 `message/rfc822`

| Column | Derivation |
| --- | --- |
| `uid` | the first msg-id of `Message-ID` (RFC 5322 §3.6.4), bare, read as below; `NULL` when absent or unparseable |
| `title` | `Subject`, decoded as an unstructured value (below); `''` when absent |
| `sender` | the first `From` address, canonical (A.6) |
| `sender_name` | its display name (below); `NULL` when it has none |
| `date` | `Date` as an instant, read as below; `NULL` when absent or unparseable. From a server-side summary, the `Date` field the server states (IMAP `ENVELOPE`'s, Graph's `sentDateTime`, JMAP's `sentAt`), never a received date |
| `size` | with the body, its octets; without it, the size the source states (IMAP's `RFC822.SIZE`, Graph's `PidTagMessageSize`, Gmail's `sizeEstimate`, JMAP's `size`), which may be an estimate, `NULL` when it states none |
| `attachment` | with the body, `1` when a part the walk reads makes the attachment mark (below), `0` when none does; without it, the source's own flag where it states one (Graph's `hasAttachments`, JMAP's `hasAttachment`), else `1` when the top-level `Content-Type` is `multipart/mixed` and `0` otherwise |
| `invitation` | with the body, the first `UID` of the first `text/calendar` part in document order (RFC 6047), its transfer encoding undone and its lines unfolded, verbatim; `NULL` when no part is one, when that `UID`'s line is longer than 65,536 octets once unfolded, and without the body |
| `in-reply-to` rows | the `In-Reply-To` ids, bare, read as below |

The size and the mark read without the body are replaced by the body's own once it is read, and a writer holding the body MUST NOT write either read without it over it; a row whose body was released (§11.4) restates both at the next meta. The invitation is never cleared once read: a summary restated keeps a known one over `NULL`. A placement gaining a body the account already holds, linked rather than read (SYNC.md §6, a copy, a move, a second label), holds it as read: its `size` the body's octets, its mark and invitation those a row of the account holding that body under the link id states, a row stating its mark first. A writer reading the body as it streams derives the mark and the invitation as the whole body gives them.

**Lines.** A line of a message, in a header block or a multipart body, ends at CRLF, at a bare LF or at the end of the message. One `\r` just before the end of the message is the line break's: a header line or a delimiter ending there ends before it, so `--b--\r` last still closes its multipart. Any other `\r` not followed by a LF is the line's content: a header line holding one before its CRLF (raw `\r\r\n`) is no empty line. Content read as octets keeps every octet.

**The walk of a message's parts** reads its entities in document order, a multipart before its children: the message's own entity at depth 0, a multipart's children one deeper (RFC 2046 §5.1), a `message/rfc822` part one entity whose own parts it does not open. A multipart no closing delimiter ends is closed by the end of the entity holding it, what follows its last delimiter line being its last child (RFC 2046 §5.1.1). An entity's `Content-Type`, `Content-Disposition`, `Content-Transfer-Encoding` and `Content-ID` are read as a header field is, from their first occurrence. It reads no entity deeper than 64, and none after the 10,000th, the message's own counted: an entity left unread, with every part under it, makes no mark, no invitation, no stand-in (§14.3) and no text the search part extracts (SEARCH.md §6).

**The attachment mark** is made by a part the walk reads whose `Content-Disposition` type is any but `inline`, `attachment` or one RFC 2183 §2.8 has a reader take as `attachment`, or, stating no disposition, whose media type is neither `multipart/*` nor `text/*` and that carries no `Content-ID` (RFC 2392). Three entities never make it: the message's own entity when it is a multipart; every child of a `multipart/encrypted`; every child but the first of a `multipart/signed` (RFC 1847). The disposition type is the field's value up to its first `;`, trimmed, compared ignoring ASCII case, a field holding none stating no disposition; the media type is the `Content-Type` value up to its first `;`, trimmed and lowercased, `text/plain` when the field is absent, under a `multipart/digest` too, or when the value holds not exactly one `/` (RFC 2045 §5.2). The parts of a protocol part are walked as any other.

**Hint**: `uid`, else `alt:` followed by the decoded subject, the `date` column and the `sender` column joined by `|`, each empty when absent (`alt:Stand-up notes|2026-08-01T10:00:00Z|alice@example.org`). **Addresses**: every `From`, `To`, `Cc`, `Bcc` under its role, in document order. `References` is the search part's (SEARCH.md §9). **`sort_key`**: the `date` column, or `''`; read descending.

**Reading the header.** The identity and the `alt:` key are built from these parses, so every writer MUST read a header as follows.

- The header block ends at the first empty line. A field is unfolded by removing every line break followed by a space or a tab, the whitespace kept (RFC 5322 §2.2.3). An unfolded line splits at its first colon: the name is the bytes before it, trimmed of trailing whitespace (`Message-ID :` is `Message-ID`, RFC 5322 §4.5), and a line holding no colon is no field. A name is matched without regard to ASCII case, and a field present twice is read from its first occurrence. Its value is read as UTF-8 (RFC 6532), replaced as A.0 says.
- A **comment** is text in parentheses, nested, in which a backslash quotes the next character; a **quoted-string** is text in double quotes, holding no comment, in which a backslash quotes the next character (RFC 5322 §3.2). Where a rule below removes comments, each reads as one space. Whitespace is the space and the tab.

**An unstructured value**, `Subject` and a display name, is decoded in three steps:

1. Every RFC 2047 encoded word, wherever it stands, is replaced by its text: `=?`, a charset (an RFC 2047 token, a `*` and an RFC 2231 language dropped from it), `?`, `B` or `Q` in either case, `?`, one or more printable ASCII characters other than `?`, and `?=`. `B` is base64 (RFC 4648 §4), its trailing `=` optional; `Q` is RFC 2047 §4.2's, `_` a space and `=` with two hexadecimal digits of either case one octet. The octets are decoded in the charset when its name, matched without regard to ASCII case, is a label of the WHATWG Encoding Standard naming an encoding other than its replacement encoding, by that encoding's decoder, with no byte order mark sniffed (`iso-8859-1` and `us-ascii` so name windows-1252, and a legacy charset is read through its index, which a writer therefore carries). The labels, the indexes and the decoders are those of the Encoding Standard as last updated on 19 October 2026, its commit snapshot be17ac5c49881336538acfc7b40dba3c8009144b; a writer on a later one reads every label and octet sequence that snapshot defines as it does. A word whose charset is no such label, a `B` word holding a character outside the alphabet, an `=` anywhere but in a trailing padding of at most two, or a length, padding aside, leaving one character beyond whole groups of four, and a `Q` word holding an `=` not followed by two hexadecimal digits are malformed, and each stays as its literal text.
2. Whitespace standing between two decoded words, and nothing else, is removed (RFC 2047 §6.2).
3. Whitespace is trimmed from both ends; whitespace inside, a tab included, stays.

**A display name** is the text of a mailbox before its `<`, its comments removed, each quoted-string replaced by its content with its quoted pairs undone, then decoded as an unstructured value; a mailbox with no `<` has none, and an empty one is none. An address list splits at the commas outside a quoted-string, a comment and angle brackets, a group listing its own mailboxes, its name, colon and closing `;` dropped. A mailbox's address is the text between its angle brackets, else its whole text with its comments removed, trimmed, then made canonical (A.6).

**`Message-ID`** names the field's first msg-id. Read from its start, comments are skipped; at the first `<` outside one, the id is the text up to the next `>`, trimmed, and the field is unparseable when no `>` follows or that text is empty. A field with no such `<` is read bracketless: its comments removed and trimmed, it is the id when it holds no whitespace, no `<`, `>` or `"`, and exactly one `@`, and unparseable otherwise. An id keeps its case. **`In-Reply-To`** lists every msg-id of the field read the same way, empty ones dropped; a field with no such `<` lists, its comments removed, each of its whitespace-separated words a bracketless `Message-ID` would take.

**`Date`** is the `date-time` of RFC 5322 §3.3 with the obsolete forms of RFC 5322 §4.3; any other value is unparseable.

- Comments are removed. The text up to and including the first comma, when there is one, is the day of the week, skipped and never checked.
- What remains is five words separated by whitespace, whitespace around a colon not counting: the day, one or two digits; the month, `Jan` to `Dec` without regard to case; the year, two digits or more; the time, `hh:mm` or `hh:mm:ss`, two digits each; the zone. Nothing follows them.
- A two-digit year below 50 is in the 2000s, one of 50 or more and a three-digit year in the 1900s (`26` is 2026, `96` 1996, `126` 2026). The year is then 1900 to 9999.
- The zone is `+` or `-` and four digits `hhmm`, `mm` at most 59, `-0000` reading as `+0000`; or, without regard to case, `UT` and `GMT` at `+0000`, `EDT` at `-0400`, `EST` and `CDT` at `-0500`, `CST` and `MDT` at `-0600`, `MST` and `PDT` at `-0700`, `PST` at `-0800`; or one letter other than `J`, a military zone, at `+0000`. A missing zone, or any other, is unparseable.
- The day exists in its month and year (29 February in a Gregorian leap year alone), the hour is 00 to 23, the minute 00 to 59 and the second 00 to 60, a leap second's 60 read as 59. Anything out of range, `30 Feb` and `24:00` among it, is unparseable, never carried over.
- The instant is the stated time less the zone's offset; one past the year 9999 is unparseable.

**A server-side summary** agrees with the body where it serves the field raw: a header field fetched as such (IMAP's `BODY.PEEK[HEADER.FIELDS (…)]`, Gmail's metadata headers, JMAP's `header:…:asRaw:all`, Graph's `internetMessageHeaders`), and the date, subject and message-id strings of an IMAP `ENVELOPE`, each read by the rules above. A source listing every occurrence of a field is read from the first: JMAP's `header:Subject:asRaw:all`, first element, never `header:Subject:asRaw`, which answers the last; the first entry of that name in Gmail's metadata headers and in Graph's `internetMessageHeaders`. A value the server decodes or parses itself (JMAP's `subject`, `sentAt` and `from`, Graph's `subject`, `sentDateTime` and `from`, an `ENVELOPE` address's name) need not agree. A writer holding the body MUST NOT write such a value over the body's, as for the size and the mark. A link id derived from one is kept once resolved (SYNC.md §6), a missed dedup (§9), so a writer SHOULD read the fields of the hint raw, as a connector MUST read the three a member is compared by (SYNC.md §4).

**The fields §9 compares are read raw.** The subject, `date` and `sender` are derived from the raw `Subject`, `Date` and `From` wherever the source serves them (SYNC.md §4): on IMAP the `ENVELOPE`'s subject and date strings and the `From` field fetched as a header field; on Gmail the metadata headers; on JMAP `header:Subject:asRaw:all`, `header:Date:asRaw:all` and `header:From:asRaw:all`, first element; on Graph `internetMessageHeaders`, which it answers only to a request selecting it and only for the messages it holds header fields for. A member a source answers none for is named from the server's decoded values, and kept apart from its own message where they differ, a missed dedup, until its body is read, which restates its row and never its key. A raw field carried inside JSON holds text: the agreement is owed for a field whose bytes are well-formed UTF-8, and one holding other octets reads as its server rendered them.

### A.2 `text/vcard`

| Column | Derivation |
| --- | --- |
| `uid` | `UID` verbatim |
| `title` | `FN`, decoded; `''` when absent |
| `card_kind` | `KIND` lowercased (`individual`, `group`, `org`, `location`) |
| `org` | the first component of the first `ORG`, decoded |

**Hint**: `uid`, else `hash:` followed by the sixteen lowercase hexadecimal digits of the FNV-1a 64 digest of the bytes. A card resolves at `Full` only, carries no flags (a known-empty set), and is mutable. **Addresses**: every `EMAIL` under `email`, canonical, with no name. **`sort_key`**, the **fold** of `fn`: `FN` decoded, lowercased by the default full lowercase mapping of Unicode 15.0.0 (UnicodeData.txt and the unconditional mappings of SpecialCasing.txt; Rust's `str::to_lowercase`, Java's `toLowerCase(Locale.ROOT)`), locale-independent, then trimmed; read ascending, a nameless card first. Of SpecialCasing.txt's conditional mappings Final_Sigma alone applies: a capital sigma ending a word (U+03A3, in the context Unicode §3.13 defines) maps to U+03C2, and to U+03C3 elsewhere. The trim removes, from both ends, the characters of the White_Space property of Unicode 15.0.0 (U+0009 to U+000D, U+0020, U+0085, U+00A0, U+1680, U+2000 to U+200A, U+2028, U+2029, U+202F, U+205F and U+3000). A writer on a later Unicode version maps every character 15.0.0 assigns as 15.0.0 does. A character assigned later, which no vector holds, MAY map as the writer's version says, a missed seek or a mis-sort being the cost.

### A.3 `text/calendar`, `VEVENT`

**The item is the calendar object resource.** RFC 4791 §4.1 keeps the components sharing a `UID` in one resource, so a series and its `RECURRENCE-ID` overrides are one item, one blob, one key. A connector to an instance-granular source MUST reassemble the set. A resource holds one component type, so its summary is one row of component `event`, `task` (A.4) or `journal` (A.5); a component of another type (`VFREEBUSY`) is an item with a body and no summary row. A second resource under one `UID` is minted and kept (§9).

| Column | Derivation |
| --- | --- |
| `uid` | `UID` verbatim |
| `title` | `SUMMARY`, decoded; `''` when absent |
| `location` | `LOCATION`, decoded |
| `dtstart`, `dtstart_tzid`, `dtstart_value` | `DTSTART` verbatim, its `TZID`, and `date-time` or `date` |
| `dtend` | `DTEND` verbatim; a `DURATION` is not resolved |
| `recurring` | `1` with an `RRULE` or `RDATE`, `0` when looked and none, `NULL` when not looked |
| `until` | the `RRULE`'s `UNTIL` verbatim |

Each column is read from the master: the first component of the resource's type carrying no `RECURRENCE-ID`, in document order, else, for a resource holding overrides alone, the first carrying one, which stands for the master in every rule of this section and of A.4 and A.5 (its `recurring` then `0` and `until` `NULL` unless it states a rule). Times are verbatim with their parameters, never resolved, but for the `sort_key`. **Hint**: `uid`, else `hash:` on A.2's terms; mutable, no flags. **Addresses**: `ORGANIZER` and every `ATTENDEE` under their roles, `mailto:` stripped, canonical, the `CN` parameter as the name.

**`sort_key`**: the master's `DTSTART` as an instant, read ascending. A UTC date-time is taken as is. A zoned one, carrying a `TZID`, resolves through the first of these that names its `TZID`, matched byte for byte: the resource's own `VTIMEZONE`, then the IANA time zone database (RFC 7809); a `TZID` neither names reads as floating. A `VTIMEZONE` observance's `RRULE` is followed for at most 1,000,000 periods from its `DTSTART`, a period counted as SEARCH.md §7 counts one, the offset of the last onset found standing beyond them, so a hostile rule costs every writer one bounded walk and gives one key.

A wall time a transition makes ambiguous or skips takes the UTC offset in effect before the transition (RFC 5545 §3.3.5): of an ambiguous one the earlier instant, and a skipped one read at the offset before the gap, so `DTSTART;TZID=America/New_York:20260308T023000` is `2026-03-08T07:30:00Z`. A date-only value reads as `T00:00:00Z`; a floating date-time reads as UTC. A series keys on its first occurrence, which `until` bounds for a reader that must expand it (SEARCH.md §7). Nothing parseable keeps `''`.

### A.4 `text/calendar`, `VTODO`

A task's row carries `uid`, `title`, `dtstart` with its parameters, `recurring` and `until` on A.3's terms, and:

| Column | Derivation |
| --- | --- |
| `due`, `due_tzid`, `due_value` | `DUE` verbatim, its `TZID`, and `date-time` or `date` |
| `status` | `STATUS` uppercased verbatim |
| `completed` | `COMPLETED` verbatim |
| `percent` | `PERCENT-COMPLETE` as an integer |
| `priority` | `PRIORITY` as an integer, 0 to 9 (RFC 5545 §3.8.1.9); `NULL` when absent or out of range |
| `parent` | the value of the first `RELATED-TO` whose `RELTYPE` is `PARENT` or absent (RFC 5545 §3.2.15), verbatim |
| `mid` | the message the first `ATTACH` or `URL` holding a `mid:` URI (RFC 2392) names: its message-id part, before any `/`, percent-decoded, bare |
| `created` | `CREATED` as an instant on A.3's rules, else `DTSTAMP` as one (RFC 5545 §3.8.7.1, §3.8.7.2); `NULL` when neither reads as one |
| `category` rows | every `CATEGORIES` value in document order, each property's list split on unescaped commas and decoded, empty values dropped |

No column carries an `X-` property. **Addresses**: A.3's, and every `CONTACT` (RFC 5545 §3.8.4.2) under `contact`: its address the one its `ALTREP` names when that is a `mailto:` URI, else its text, canonical either way (A.6); its name its text decoded, `NULL` when the address was read from a text that is an addr-spec; a `CONTACT` with an empty text and no such `ALTREP` files no row. **`sort_key`**: `DUE`, else `DTSTART`, as an instant on A.3's rules; `''` when neither.

### A.5 `text/calendar`, `VJOURNAL`

A journal's row carries `uid`, `title` and `dtstart` with its parameters on A.3's terms. **`sort_key`**: `DTSTART` as an instant, or `''`.

### A.6 Addresses

An item's addresses are its `summary_value` rows of the address roles, one per address per role, in document order within the role: `from`, `to`, `cc`, `bcc` for mail, `email` for a card, `organizer` and `attendee` for a calendar object, `contact` for a task. The **canonical address**, the row's `value`, is the addr-spec alone, display name, comments, angle brackets and `mailto:` removed, lowercased whole by A.2's mapping (`İ` becomes `i` and a combining dot above); a value that is not an addr-spec is kept lowercased as it is. The **name** is the display name decoded, or `NULL`; a card's addresses have none.

### A.7 `application/octet-stream`

A file's summary is what its source or its writer states, its bytes saying nothing about it.

| Column | Derivation |
| --- | --- |
| `title` | the file's name in this collection, as its folder or source states it, or an attachment's `filename` (`Content-Disposition`, else the `Content-Type` `name`, RFC 2231 and RFC 2047 decoded, an RFC 2231 value whose charset is no label A.1 decodes read as UTF-8, replaced as A.0 says); `''` when none |
| `media_type` | the type and subtype as stated (an attachment's `Content-Type`), lowercased, parameters dropped; `NULL` when unstated |
| `size` | with the body, its octets; without it, as stated: an attachment's decoded octets (its body with its `Content-Transfer-Encoding` undone, the line break before the next delimiter belonging to the delimiter, RFC 2046 §5.1.1; `NULL` for a `multipart` part), or the source's figure |
| `part` | for an attachment, its section in the message's body (RFC 3501 §6.4.5, `1`, `2.1`), counted on the body as stored; `NULL` otherwise |

The size read without the body is replaced by the body's own (A.1). **Hint**: none; `uid` is `NULL`. An attachment is keyed `part:`, its message's `link_id`, `#` and its `part` (`part:abc@host#2`). A file created in the store is keyed `file:` and 32 lowercase hexadecimal digits of 128 random bits. A file a source lists is keyed by the id its server keeps across a rename and a move, which is also its handle (SYNC.md §4). A file carries no flags (a known-empty set) and no addresses. **`sort_key`**: `title` folded as A.2 folds `FN`, read ascending.

## Annex B. Capabilities (normative)

A capability's name is lowercase words of letters, digits and hyphens joined by periods. The first word is its domain, which fixes the kind: `mail` is `message/rfc822`, `contacts` is `text/vcard`, `calendar` is `text/calendar`, and `collection` holds for every kind, read for the kind of the collection an action is anchored on, a declaration writing it whatever kinds the source syncs. The words after it name an object and a verb (`mail.message.move`), a flag (`mail.flags.seen`), a feature (`calendar.scheduling`) or an intent (`mail.submit`), one more word naming an option of an intent (`mail.submit.copy`).

A name is never given another meaning: a new behaviour takes a new name. A name beginning with `x-` is an application's own, and this part defines none.

The table names every capability this part defines. Each forms the **base set** (§15.6), read as unsupported where a declared source has no row for it, but `calendar.component.vtodo`, `mail.flags.important` and `mail.flags.junk`, each read only where a row states it, as is a name added after `storage-v1.0.0`, which the table marks with the version adding it.

| Capability | Kind | Needed by |
| --- | --- | --- |
| `mail.message.add` | `message/rfc822` | an `add` |
| `mail.message.copy` | `message/rfc822` | a `copy` |
| `mail.message.move` | `message/rfc822` | a `move` |
| `mail.message.remove` | `message/rfc822` | a `remove` |
| `mail.flags.seen` | `message/rfc822` | a flag change on `\Seen` (B.1) |
| `mail.flags.flagged` | `message/rfc822` | a flag change on `\Flagged` |
| `mail.flags.answered` | `message/rfc822` | a flag change on `\Answered` |
| `mail.flags.draft` | `message/rfc822` | a flag change on `\Draft` |
| `mail.flags.important` | `message/rfc822` | a flag change on `$Important` (RFC 8457); read only where a row states it (B.1) |
| `mail.flags.junk` | `message/rfc822` | a flag change on `$Junk` (RFC 9051 §2.3.2); read only where a row states it (B.1) |
| `mail.flags.keywords` | `message/rfc822` | a flag change on any other flag, and on `$Important` or `$Junk` for a source stating no row for theirs (B.1) |
| `mail.submit` | `message/rfc822` | a `submit` (B.2) |
| `mail.submit.copy` | `message/rfc822` | a `submit` naming `copy`, beside `mail.submit` |
| `contacts.card.add` | `text/vcard` | an `add` of a card |
| `contacts.card.update` | `text/vcard` | an `update` of a card |
| `contacts.card.remove` | `text/vcard` | a `remove` of a card |
| `contacts.card.move` | `text/vcard` | a `move` of a card |
| `contacts.card.copy` | `text/vcard` | a `copy` of a card |
| `calendar.item.add` | `text/calendar` | an `add` of a calendar resource |
| `calendar.item.update` | `text/calendar` | an `update` of a calendar resource |
| `calendar.item.remove` | `text/calendar` | a `remove` of a calendar resource |
| `calendar.item.move` | `text/calendar` | a `move` of a calendar resource |
| `calendar.item.copy` | `text/calendar` | a `copy` of a calendar resource |
| `calendar.occurrence.update` | `text/calendar` | an `update` that changes an occurrence (B.1), beside `calendar.item.update` |
| `calendar.scheduling` | `text/calendar` | an `add` or `update` whose new resource, or a `remove` whose current one, is scheduled (B.1) |
| `calendar.online-meeting` | `text/calendar` | an `add` or `update` asking for an online meeting (B.1) |
| `calendar.component.vtodo` | `text/calendar` | an `add` or `update` whose new resource is a VTODO, and a `move` or `copy` of one, in the collection it lands in; read only where a row states it (§15.6) |
| `calendar.reply` | `text/calendar` | a `calendar-reply` (B.2) |
| `calendar.reply.occurrence` | `text/calendar` | a `calendar-reply` naming `recurrence_id`, beside `calendar.reply` |
| `calendar.cancel` | `text/calendar` | a `calendar-cancel` (B.2) |
| `calendar.cancel.occurrence` | `text/calendar` | a `calendar-cancel` naming `recurrence_id`, beside `calendar.cancel` |
| `collection.create` | the anchor's | a `collection-create` (B.2) |
| `collection.rename` | the anchor's | a `collection-rename` (B.2) |
| `collection.delete` | the anchor's | a `collection-delete` (B.2) |

### B.1 State

What a source pushes when the owner applies a §15.3 action, read by the owner's backstop and the producer's gate (§15.6) against the sources concerned.

A **flag change** is a flag a `set-flags` adds or removes against the item's current set, or one an `add` or `copy` carries into the collection, whose set starts empty there: a `set-flags` restating a flag needs nothing for it, a draft added with `\Draft` needs `mail.flags.draft`. A `set-flags` stating `base` is read against the current set too, never against `base`, so a flag it adds that a sync landed meanwhile needs nothing.

A flag names its capability compared without regard to ASCII case, as IMAP compares flags and keywords (RFC 9051 §2.3.2), so `$important` is `$Important`. A change on `$Important` or `$Junk` needs `mail.flags.important` or `mail.flags.junk` from a source stating a row for it, `none` included, and `mail.flags.keywords` from one stating none: a source carrying these two as fields of its own while taking no arbitrary keyword (Gmail's `IMPORTANT` and `SPAM` labels, Graph's `importance`) supports them without `mail.flags.keywords`.

A resource is **scheduled** when one of its components names an `ATTENDEE` and some `ORGANIZER` or `ATTENDEE` of that component lacks `SCHEDULE-AGENT=CLIENT` or `SCHEDULE-AGENT=NONE` (RFC 6638 §7.1). A source supporting `calendar.scheduling` notifies the attendees of what it pushes (RFC 6638 §3.2).

An `add` or `update` **asks for an online meeting** when its new resource carries `X-PIMDIR-ONLINE-MEETING:TRUE` on a component the current one does not. A source supporting `calendar.online-meeting` creates an online meeting of its provider with the resource and removes the property, the join details arriving with the next sync as `CONFERENCE` (RFC 7986 §5.11). The property is an instruction, never content: §18 says who may write it.

A scheduled resource for a source without `calendar.scheduling` is parked by the owner's backstop, and a producer that gates refuses it, unless the user accepts that nobody is notified. A producer recording that acceptance MUST write it into the resource as `SCHEDULE-AGENT=NONE` on every `ORGANIZER` and `ATTENDEE` of the component lacking `SCHEDULE-AGENT=CLIENT` or `NONE`, never as a flag of its own: the resource is then not scheduled, so the gate and the backstop read the same answer. An implementation notifying by email (RFC 6047) rather than through the server marks them `CLIENT` on what it pushes, so the server does not notify them again.

An update **changes an occurrence** when the components carrying `RECURRENCE-ID` differ between the current and the new resource, `DTSTAMP` and `LAST-MODIFIED` aside.

### B.2 Intents

Performed by the source the payload names (§15.6), outside the store, then acknowledged with its receipt (§15.5) or parked. Of the intents below, `submit` alone can end with its outcome unknown and is then parked `unconfirmed: ` (§15.2), a message handed over twice being two messages; every other is performed again when its outcome is unknown, a repeat finding its effect made or restating it. An intent addressing an item does so by `seq`, or by `link_id` when the item is still a pending `add` the producer queued, exactly one of the two. Its payload is typed and refused as §15.3 says, a performer parking what its producer should have refused.

| Action | Payload at `v: 1` | Performed as |
| --- | --- | --- |
| `submit` | `{ "v": 1, "source": id, "from": addr, "rcpts": [addr…], "subject": text?, "copy": collection? }`, the message as the action's body | the message sent with `from` and `rcpts` as its envelope, its `Bcc` field removed before transmission (RFC 5322 §3.6.3); anchored on the collection its sent copy belongs to, `subject` for reports only; with `copy`, a copy filed in that collection once sent |
| `calendar-reply` | `{ "v": 1, "source": id, ( "seq": n \| "link_id": key ), "partstat": "ACCEPTED" \| "TENTATIVE" \| "DECLINED", "comment": text?, "recurrence_id": text? }` | the account's reply sent to the item's organizer, `comment` with it (RFC 5546 §3.2.3), for the one occurrence `recurrence_id` names when present; the new `PARTSTAT` arrives with the next sync |
| `calendar-cancel` | `{ "v": 1, "source": id, ( "seq": n \| "link_id": key ), "comment": text?, "recurrence_id": text? }` | an event the account organises cancelled, the attendees notified with `comment` (RFC 5546 §3.2.5), only the occurrence `recurrence_id` names when present; the removal, or the series without that occurrence, arrives with the next sync |
| `collection-create` | `{ "v": 1, "source": id, "name": label, "parent": collection? }` | a collection named `name` created on the source's server, under `parent` when present, of the anchor's kind; it arrives with the next sync |
| `collection-rename` | `{ "v": 1, "source": id, "name": label }` | the collection the action is queued on renamed `name` on the source's server, its parent and its items kept; the new name arrives with the next sync |
| `collection-delete` | `{ "v": 1, "source": id }` | the collection the action is queued on deleted on the source's server, with the items it holds; the deletion arrives with the next sync |

A `submit` naming `copy` needs `mail.submit.copy` beside `mail.submit`, from the same performer. A performer whose provider files the sent message itself (Graph's `sendMail`, Gmail) supports it as that filing, enqueuing nothing, only when `copy` is the collection whose role is `sent` (§14); a copy elsewhere it files as its provider allows: as another label on the sent message where labels are collections (Gmail), else as an `add` of the message into `copy`, `\Seen` set, by replacing the intent (§15.5), the way a performer whose provider files nothing files every copy. A performer that can file a copy nowhere but in Sent declares `mail.submit.copy` `partial`, and `none` on its other collections, a `submit` being anchored on the collection its copy belongs to, so the gate refuses such a copy at enqueue. A provider filing every sent message says so in the `detail` of `mail.submit`. A producer asks for `copy` only of a declared performer, and against an undeclared one files the copy itself, an `add` beside the `submit`.

`calendar.reply` and `calendar.cancel` address an item and are anchored on its collection. An implementation through the provider's own verbs reaches only the items its source holds, and is declared on those collections. One over email (RFC 6047), sending the iTIP object (RFC 5546) with `METHOD:REPLY` or `METHOD:CANCEL` and the comment as `COMMENT`, reaches any item and is declared source-wide; it also writes the account's new `PARTSTAT` into the item, or removes it, marked `SCHEDULE-AGENT=CLIENT`. A source that schedules on the server and has no verb for them MAY perform them as the write its server schedules from, a `PARTSTAT` change or a removal, and declares them `partial` when `comment` is lost.

`recurrence_id` names one occurrence of a recurring item by its `RECURRENCE-ID` (RFC 5545 §3.8.4.4), the value as the item's iCalendar spells it, parameters aside, the `Z` kept when it is UTC: an overridden component or an instance its rule generates; absent, the intent addresses the whole series. The reply carries the `RECURRENCE-ID` (RFC 5546 §3.2.3); the cancel notifies the attendees of that instance alone (RFC 5546 §3.2.5) and leaves the series without it. A performer finding no such occurrence parks the row. A payload naming it needs `calendar.reply.occurrence` or `calendar.cancel.occurrence` from the same performer, which a producer names only when declared.

`collection.create` is anchored on `parent` when the payload names one, a collection of the anchor's account and kind the performer syncs, else on a collection of the account and the kind the new one takes, so a source refusing children under one collection declares `none` there (an IMAP mailbox marked `\Noinferiors`). `name` is one level of the hierarchy, a non-empty label carrying no separator of the provider, which the performer maps onto its server. The performer acknowledges the intent once the server holds the collection, one already holding it under that parent being a success; it reaches the store with the next sync, under the id its owner gives it (§9.2) and with `name` as its label.

`collection.rename` and `collection.delete` address the collection the action is queued on, which the payload does not restate, so a rename in the store (§14) leaves the row addressing it. A source keeping a collection fixed (an IMAP `INBOX`, a system folder, a default calendar) declares `none` on it. A rename changes the label alone, `name` as for `collection-create`, the parent kept; a performer finding a sibling already named `name` parks the row, and one finding the collection already so named acknowledges it. Where the owner derives the collection's id from its name (an IMAP mailbox's), the performer SHOULD follow the rename in the store (§14) when it acknowledges the intent, so the items keep their bindings.

A delete removes the collection and the items it holds, never another collection: a performer finding a collection under it on the server parks the row naming them, deleting nothing. It acknowledges the intent once the server no longer holds the collection, one already gone being a success. The deletion reaches the store with the next sync, which removes no item for it and queues no `remove`; whether another source mirroring the collection loses it too is SYNC.md §5's.
