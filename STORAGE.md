# Pimdir storage specification

Status: storage-draft-15, the base, requiring no other part, released together with the sync and search parts

The storage part of the pimdir standard, and its base: a **SQLite database** (the index and the mutable state) plus a **content-addressed blob directory** (the bodies). The two layers over it are [SYNC.md](./SYNC.md), how sources reconcile through the store, and [SEARCH.md](./SEARCH.md), the index and query language over it.

This part binds every implementation, by the profile it meets (§17): a **reader** opens the store and lists it, a **producer** also appends actions, an **owner** mutates it. The two layers presuppose the store: an implementation MAY omit either and MUST conform to those it offers.

A blob is immutable. A body edit writes a new blob and repoints the item.

[OVERVIEW.md](./OVERVIEW.md) explains the model this part fixes; [GUIDE.md](./GUIDE.md) runs its rules as procedures. Both are informative and this part wins on any disagreement.

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in BCP 14 (RFC 2119, RFC 8174) when, and only when, they appear in all capitals, as shown here. Every statement of behaviour in this part is normative: a key word marks its requirement level, and a statement carrying none binds as one carrying MUST. Notes, examples and rationale are informative and marked as such: a paragraph opening with *Note:*, an instance of what a sentence states given in parentheses or after "for example", and a reason given with "so", "since" or "because", none of which adds a requirement.

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
11. [Retention](#11-retention): [requirements](#111-requirements), [purging](#112-purging), [evicting below a date](#113-evicting-below-a-date), [releasing bodies below a date](#114-releasing-bodies-below-a-date), [erasing](#115-erasing)
12. [Collection generation](#12-collection-generation)
13. [Encodings](#13-encodings)
14. [Operations](#14-operations): [reading the store](#141-reading-the-store), [references](#142-references), [files](#143-files)
15. [Action queue](#15-action-queue): [producing](#151-producing), [applying](#152-applying), [actions](#153-actions), [reading the queue](#154-reading-the-queue), [cancelling and acknowledging](#155-cancelling-and-acknowledging), [capabilities](#156-capabilities)
16. [Test vectors](#16-test-vectors)
17. [Conformance](#17-conformance)
18. [Security considerations](#18-security-considerations)

[Annex A](#annex-a-summaries-normative) fixes the per-kind summary, address and `sort_key` derivations. [Annex B](#annex-b-capabilities-normative) fixes the capability names and the intents' payloads. Both are normative.

## 1. Goals

Pimdir is what most PIM stores already are (Apple Mail, Thunderbird, notmuch, evolution-data-server): an indexed binary store for state, the large immutable content beside it. In priority order:

- **Generic**: one store for every kind the standard names, keyed by media type. The set is closed: it grows by a change to this standard, carrying its summary table, its Annex A section and its vectors, never by a writer.
- **Scalable and indexed**: hundreds of thousands of items with real secondary indexes, never a file open per item.
- **Portable**: the SQLite file format is byte-identical across every OS and architecture, with none of the case, character and path-length pitfalls of file-per-item layouts.
- **Transactional**: a flag change or a multi-item move is one ACID commit.
- **Recoverable**: what a source holds (its items, bindings, summaries and bodies) is derived from the blobs and the remote, and is restored by re-sync (§7). The rest is not (below).

The rest exists only in the database, and no re-sync restores it: un-pushed edits and pending creates, the queue and its receipts, a person's references (§14.2), capabilities and performers, retained rows, and the collections no source syncs (§14.3). A rebuild is therefore never automatic: an implementation offers it only as an operation the user confirms, reporting first what it loses.

Any language with a SQLite binding can implement this.

## 2. Terminology

- **Store**: a directory holding one database and one blob directory.
- **Database**: pimdir.db, holding collections, items, summaries, addresses, bindings, objects, checkpoints and coverage.
- **Collection**: a mailbox, address book, calendar or folder; a row in `collections`.
- **Account**: the identity a collection belongs to, an opaque owner-chosen id in `collections.account`, `NULL` in a single-account store (§9.2).
- **Item**: one message, contact, event, task, journal or file.
- **Placement**: one item's presence in one collection, its row of `items` keyed `(collection, link_id)`: its flags, level, sort key and pointer to its object, with the binding of each source syncing it there (handle, base). One item in two collections is two placements sharing one `seq` and one object. SYNC.md projects one per source, a **projected placement** (SYNC.md §2).
- **Kind**: a collection's media type, one of §13's four, which every item it holds shares (`collections.kind`).
- **Summary kind**: the summary table an item's row is in (Annex A): mail, contact, event, task, journal or file, a calendar collection holding events, tasks and journals; a statement's `<kind>` names one.
- **Mutable**, **immutable**: a card, a calendar resource and a file are mutable, an edit replacing the body under the same key as its revision moves; a message is immutable, one identity being one body (§11.1, SYNC.md §3).
- **Tier**: what a placement holds of its item: `Meta`, its identity, summary, address rows and sort key (`level` 1), or `Full`, the body too (`level` 2).
- **Summary**: what a reader lists an item from without its body, one row in its summary kind's table (Annex A), derived by the writer, never by the store.
- **Address**: one person an item names in one role, a row of one generic table across every kind (Annex A.6).
- **Stamp**: the value of the store-wide change counter a row took when it last moved (§4.5).
- **Object**: a content-addressed, immutable body: a row in `objects`, bytes in a blob file.
- **Handle**: the backend's id for a placement in its collection (an IMAP UID, a DAV resource name).
- **Link id**: the item's key in its collection, assigned from the identity hint the content states (`Message-ID`, `UID`) and equal to it unless the collection already holds it (§9).
- **Pending create**: a binding with no base, a source's create waiting for its add to be accepted, under a **provisional handle**: `U+0001` followed by the link id, a name no server hands out (SYNC.md §2). A **delivered create** is one its source took before any listing named it: its binding keeps the provisional handle and holds a base naming nothing (SYNC.md §2).
- **Held**: a key is held in a collection when a row of `items` there has it, live, tombstoned or retained, and free otherwise (§9).
- **Hash**: the content hash of an object's bytes, BLAKE3 in base32 (§5): its integrity value, dedup key and blob name, never a path.
- **Source**: one remote the store syncs a collection with or performs an intent through, a server account over one protocol or another device, under an owner-chosen id, never empty, naming one remote store-wide (§4.3): the `source` of `sources`, `bindings`, `capabilities` and `performers`. An item's sources are those binding it.
- **Checkpoint**: an opaque per-source cursor (QRESYNC state, JMAP state, DAV sync-token).
- **Batch**: the operations a writer folds into the store in one transaction, in order (§14); an operation cut into several batches writes them as its **chunks**.
- **Sync state**: the rows an engine writes for its sources, bindings, sources and the cross-source columns of items, which `store_meta.sync_version` says the version of (§14).
- **Scope**: `[since, until)` on a message's summary `date`, either bound open, under which a source syncs a mail collection (SYNC.md §5).
- **Round**: one complete listing of a scope by one source, in pages, under an id; it stamps the bindings it lists (SYNC.md §5).
- **Coverage**: the scope of a source's last round that closed and when it closed: the store holds every member of the collection the source has in that scope, and the checkpoint serves it.
- **Retained item**: an item no source holds any more, kept and hidden until purged (§11).
- **Eviction**: the owner's removal, on request, of the mail of a collection below a date that owes nothing (§11.3): no delete, no purge and nothing pushed, the remote keeping every member.
- **Writer**: whoever writes rows of the store: the owner, an engine through it (§14), a producer enqueuing (§15).
- **Consumer**: a program deriving state from the store and following its change feed (§4.5): the search index, a reader's window.
- **Engine**: an owner's program reconciling the store with its sources by SYNC.md's verbs, reading each source through a **connector**, which answers for one source over one protocol (SYNC.md §4).
- **Owner lock**: the exclusive advisory lock on owner.lock the owning process holds (§8).
- **Staging lock**: the advisory lock on objects.lock producers hold shared while a body is written but not yet referenced, and the collector takes exclusively (§5, §8).
- **Quarantine**: the directory an owner moves a body failing its name into, never read as a body nor collected (§7).
- **Action**: a mutation a producer appends to the queue for the owner to apply, named (`add`, `set-flags`, an intent's name, an application's own) and carrying a payload of its version (§15.3).
- **Capability**: something a source can push or perform, named by Annex B, declared by the owner per source (§15.6).
- **Intent**: a queued action performed by one source outside the store, a mail submission for one (Annex B.2).
- **Performer**: the source performing an intent, named in its payload, chosen by the user when several could (§15.6).

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

A directory is a pimdir store if and only if it contains a pimdir.db whose `store_meta.format` is `'pimdir'`. The lock files are empty, created by the first handle that takes one, and hold no state. The quarantine/ directory is created by the first move into it.

The index is derived and droppable.

**One name is the owner's.** The subdirectory local/ is reserved for the state an owner keeps of its own beside the store: its configuration, a lock of its own, a mark of work under way. The owner creates it when it first needs it, with mode `0700` (§18). This standard never defines what it holds: a reader and a producer ignore it, the collector never walks it, no rule of this document reads it, and a backup copies it with the store (§8). State kept there that follows the store is a consumer's, checked against the store's id and incarnation as §4.5 says.

No other file belongs in the directory, an implementation's own included: what an implementation keeps of its own is under local/ or outside the store directory (§6). An implementation MUST ignore a file it does not own, save the temporaries the collector removes (§5), and the collector walks objects/ only, never quarantine/ nor local/.

## 4. The database

### 4.1 Requirements

- The database MUST be a SQLite database named pimdir.db, holding the schema under migrations/storage/, which is the store's one on-disk format.
- The schema loads on **SQLite 3.18** or later: every table, index and trigger it creates, and every insert, update and delete into its tables, compiles there. A column's type is held by `CHECK (typeof(…))`, never by `STRICT`, so every implementation opens the same store whatever SQLite it links.
- The statements under queries/storage/ are RECOMMENDED verbatim and need **SQLite 3.37** or later, for `RETURNING`, upserts, `UPDATE … FROM` and the `STRICT` temporary table of the list parameters (§4.4); they call no JSON function and no extension. An implementation MAY run statement text of its own, on any SQLite the schema loads on, keeping what §4.4 binds.
- `PRAGMA foreign_keys = ON` MUST be set per connection, and so MUST `PRAGMA synchronous = FULL` or `EXTRA`: a commit a power loss undid would hand out again a queue id, a `seq` or a change stamp a producer or a consumer already recorded (§4.5, §9.1, §15). A connection that writes also sets `PRAGMA secure_delete = ON` (§11.5).
- `PRAGMA journal_mode = WAL` is RECOMMENDED for a local store, with a `PRAGMA journal_size_limit`, so a WAL one large write grew is truncated once checkpointed; see §8 for a network filesystem.
- pimdir.db is created with `PRAGMA auto_vacuum = INCREMENTAL`, which a database takes only while it holds no table: 0001_init.sql sets it before its first. An owner MAY run `PRAGMA incremental_vacuum` after the collector's run, a purge, an eviction or a release (§5, §11) to give the freed pages back to the filesystem.
- A reader and a producer SHOULD set a busy timeout (`PRAGMA busy_timeout`, or its driver's), so the owner's write transaction delays a read or an enqueue rather than failing it.

### 4.2 Schema version

`store_meta.format_version` names the version of this part whose schema the store holds: this draft's name, `storage-draft-15`, while this part is a draft, and `storage-vN` once released, N its major alone. `init_store_meta` writes it when the store is created, and `set_store_version` with every migration (§6).

**A draft's store opens under that draft alone.** While this part is a draft, a program of any profile MUST refuse a store whose `format_version` is not its own draft's name, naming both, and a store lacking the column, which a draft before storage-draft-08 wrote. A released program refuses every draft store the same way, so no draft store is carried into a release. A refused store is never reconciled, migrated, rebuilt nor written, and never deleted.

**Which store is the earlier.** Format versions are ordered: none first, a store lacking the column, then the drafts by the number after `storage-draft-`, read as a decimal integer (`storage-draft-08` before `storage-draft-15`), then the releases by their major (`storage-v1` before `storage-v2`), every draft before every release. A program refusing a store for its `format_version` MUST say, by this order, which of the two is the earlier, and what that asks: a store below its own was written by an earlier engine, whose queued writes it alone holds, so the user syncs it with that engine until nothing is queued, then moves its directory aside and syncs a new store; a store above its own asks for a later program. A marker this order does not read (another prefix, no number, a release's major with a leading zero) is named as it stands, and the refusal orders it neither way. No refusal advises deleting the store. vectors/versions.json pins the order.

The schema version is `PRAGMA user_version`, mirrored in `store_meta.version`. The two MUST agree; a store where they disagree is corrupt. Both move together, only in the transaction applying a migration (§6).

This part's major version is the schema version: `storage-vN.x.y` defines version N. A minor version adds a rule, a statement or a vector and breaks no store; a patch is editorial.

Version 1 is [migrations/storage/0001_init.sql](./migrations/storage/0001_init.sql). While this part is a draft, version 1 is edited in place and `user_version` stays `1`, `format_version` telling one draft's store from another's. Once version 1 is released, 0001_init.sql never changes, and every later schema change is a migration to the next version (§6).

**Compatibility versions.** Beside `version`, `store_meta.read_version` is the lowest schema version a program must implement to read the store, and `store_meta.produce_version` the lowest it must implement to enqueue into it (§15). Each migration states which it raises (§6). Once this part is released:

- an owner opens only a store whose `version` it knows, any version up to its own, and migrates it to its own (§6);
- a reader opens a store whose `read_version` is at most its own schema version;
- a producer, one whose `read_version` and `produce_version` both are.

A reader or a producer opening a store below its own version reads it as that version defines it. While this part is a draft the exact `format_version` governs alone, and the three stay `1`.

**A store above a program's version is judged by `store_meta` alone.** A released reader or producer opening a store whose `version` is above its own MUST judge it by six columns of `store_meta` and by nothing else of the schema: `format` is `pimdir`; `format_version` is `storage-v` followed by `version`, a draft's name being refused; `version` equals `PRAGMA user_version`; `read_version`, and for a producer `produce_version` too, is at most its own version; `hash_algo` is one it knows (§6 step 2). These six columns keep their name, their type and their meaning in every version of this part: no migration renames, drops nor redefines one.

Such a program MUST NOT refuse the store, nor read it as corrupt, for a `user_version` above its own, nor for a table, a column, an index, a trigger or a view it does not know: a later version's schema is not its own to verify, and its statements name their columns (§4.4), so what that version added moves nothing they read or write. It reads, and enqueues, as its own version defines. What it compares of the schema's text is §18's, against a version it knows alone.

### 4.3 Tables

The canonical schema is migrations/storage/0001_init.sql, which is normative. This section is its prose companion.

- **`store_meta`** (one row): `format`, `format_version` and the schema versions `version`, `read_version` and `produce_version` (§4.2), the store's identity `store_id` and `incarnation` (§4.5, §8), `hash_algo` (`blake3`, the one algorithm of §5), `created_at`, `derivation` (the Annex A revision the rows stand under, §6), `sync_version` (the sync part the sync state follows, §14), and the counters `next_seq` (§9.1), `next_change` and `purges` (§4.5).
- **`collections`**: `id`, `account` (§9.2), `kind` (the media type every item shares, one of the four of §13 or `''` until declared; `x-` names capabilities, reference roles and queue actions, never a kind), `name`, `parent` (hierarchy by reference), the presentation columns `color`, `description`, `sort_order`, the `role` a source states (§14), the cross-source `conflict` policy, `generation` (§12) and `changed` (§4.5).

  Every foreign key onto `id` is `ON UPDATE CASCADE`, so a rename keeps its contents (§14); `ON DELETE` is `CASCADE`, `SET NULL` for `parent` and for a receipt's `collection` (§15.4).
- **`sources`**: one row per source syncing a collection, keyed `(collection, source)`, carrying its `checkpoint`, its coverage and its round (§10).

  Its **coverage**: `covered_since` and `covered_until`, the scope of its last round that closed, and `covered_at`, when it closed, `NULL` for never.

  Its **round**: `round`, the last id drawn, and while one is open: `round_started_at`; its scope `round_since` and `round_until`; `round_band`, whether it lists only the band the coverage lacks; its resume cursor `round_cursor`; and `round_checkpoint`, the checkpoint it will land, the latest a page or a head handed.

  The schema holds that no coverage carries no bound and no open round carries nothing. A source id names one remote store-wide, so an owner filing two accounts keeps their source ids apart, as it does their collection ids (§9.2).
- **`capabilities`**: what each source can do, one row per `(source, collection, capability)` carrying the `account` the source syncs for, `collection` `NULL` for the source-wide row and naming a collection where the source does otherwise there, with its `support` and a `detail` for a human (§15.6).
- **`performers`**: the source the user chose to perform an intent capability for an account, one per `(account, capability)` (§15.6).
- **`objects`**: `hash` (primary key, a name of §5, its shape held by a `CHECK`), `size`, `refcount` (§5, §7). The bytes live in the blob file.
- **`items`**: the shared truth of one item, keyed `(collection, link_id)`, its placement id `id` the key every child of it carries (never reused and never shown: a consumer keeps `(collection, seq)`, §9.1): `seq` (§9.1), `flags_known` (whether its flag set is known, §13), `marks` (its system flags, §13), `object_hash`, `sort_key` (§9.3), `level` (1 meta, 2 full), the cross-source state `deleted`, `conflicted`, `conflict_object`, the retention stamps `retained_at`, `retained_by` (§11), and `changed` (§4.5).
- **`mail_summary`**, **`contact_summary`**, **`event_summary`**, **`task_summary`**, **`journal_summary`**, **`file_summary`**: one table per kind, at most one row per item, keyed by its `item`, cascading with the item, referencing no object. Their columns are Annex A's, so a writer that disagrees with the schema fails at the write. A list Annex A derives is a table of its own, one row per value in document order (`position`), cascading with its summary row: **`mail_in_reply_to`** the `In-Reply-To` ids (`mail_in_reply_to_by_id` answering `list_replied`), **`task_category`** a task's categories.
- **`placement_flag`**: one row per flag of a placement whose set is known, but for the system flags `items.marks` holds (§13), keyed `(item, flag)`, cascading with the item; `placement_flag_by_flag` answers a flag predicate by a seek.
- **`item_address`**: the people an item names, keyed `(item, role, position)` (Annex A.6). One table across every kind, so "everything about this address" is one seek on `item_address_by_address`.
- **`item_reference`**: a reference between two items (§14.2), keyed `(from_link_id, from_kind, to_link_id, to_kind, role)`, each endpoint a kind and a link id held by no foreign key, with its `role`, `origin` and `created_at`; `item_reference_to` serves the other end.
- **`bindings`**: one source's binding of an item, keyed `(item, source)`, its `collection` the item's, held so by a foreign key onto `items(id, collection)` that a rename cascades through: the `handle`, the sync base (`base_flags_known`, `base_marks`, `base_object`, `base_revision`, `base_present`, its other flags in **`binding_base_flag`** on `placement_flag`'s terms), the `shared_object` last agreed with the item, the conflict triple `conflicted`, `conflict_revision`, `conflict_object`, `round`, the id of the last round that listed the handle (§10), and the refusal standing on it, `refusal`, `refused_key` and `refused_at` (§13, SYNC.md §5).

  A handle is bound once, never repointed, and names one item per source (§10): `bindings_by_handle` is unique.
- **`supersessions`**: what an `add` carrying `supersedes` replaced (§15.3), keyed by the `item` it tombstoned, with `by_item` the item it created; each end cascades with its item.
- **`queue`**: the action queue (§15): `id`, `created_at`, `producer`, `collection`, `action`, `payload`, `target_collection` (the collection a payload names, §15.3), `object_hash`, `attempts`, `error`.
- **`receipts`**: what an applied queue row or a performed intent became, keyed by its `id`: `applied_at`, the `collection` it was queued on, `NULL` once that collection is gone, and the `seq` of the item it acted on or created (§15.2, §15.4, §15.5).

**Rows and indexes.** A table whose rows are a few short columns keeps no rowid: `placement_flag`, `binding_base_flag`, `item_address`, `mail_in_reply_to`, `task_category`, `item_reference` and `supersessions` are `WITHOUT ROWID`, a row stored once, in its key's order. An index on a pointer at an object holds the rows whose pointer is set (`items_by_object`, `bindings_by_object`, `bindings_by_shared_object`, `bindings_by_conflict_object`, `items_by_conflict_object`, `queue_by_object`), which an equality implies, so an object's delete checks its foreign keys there; `items_bodiless` holds the other side, each collection's live rows holding no body, which the search part's `coverage` counts per collection (SEARCH.md §8.2). `bindings_refused` holds the bindings a refusal stands on, which `list_refusals` reads (§14.1). `items_unread` holds each collection's live unread mail in its order, which `count_unread` reads (§13, §14.1), `items_deleted` every deleted row of a collection by `seq`, the trash view's (§11.1), `items_by_retained` the retained rows by the instant they were retired (§11.2), and `items_by_seq_global` a public id whatever its collection, which a search hit names without one (SEARCH.md §8.2). No index orders the items of several collections together: a page over a set merges each collection's order (§9.3).

An item plus one binding per source is the whole model. Single-source is the N=1 case; N≥2 adds only `deleted`, a removal that lingers until every source has dropped it.

### 4.4 Queries

The named, parameterised statements servicing §14 live under [queries/storage/](./queries/storage/), one file per statement named after it, sorted by the profile that runs it: read/ is the reader's (§14.1), queue/ the producer's (§15.1), owner/ the rest, an owner running all three. An implementation reads them by listing its directories. A file's leading comment says what the statement alone cannot; the rules are this document's.

**What a name binds.** A canonical name binds the text run under that name: the name, its named parameters, the columns it answers, in order, and its effect. The canonical text is a reference, RECOMMENDED verbatim (§4.1). An implementation running text of its own under a canonical name MUST keep all four, the rules this document states and §7's invariants. Its text for one name MAY be several statements, run in order in one transaction, the caller's or one it opens, so long as it keeps them: no other connection's write comes between them, and the name answers the rows the one statement answers.

**An effect may be reached otherwise.** An implementation MAY reach the effect a section states through statements of its own, under names of its own, in place of the canonical ones that section names (a write folding a batch in fewer statements, a collector deleting what it lists in one). Such statements are bound by §7's invariants, by the column rule below, by every rule this document states for that effect and by the vectors (§16), and none of them takes a canonical name while differing from it in a parameter, a column or its effect. Where this document says that an operation runs a statement, in §14, §15 and elsewhere, it describes the reference form: what binds is the effect that statement has, in the transaction and the order stated, reached by that statement or by another.

**What a change costs.** Once this part is released, a fix to a statement's text keeping its parameters, its columns and its effect is a patch; a statement added is a minor version; a change to a statement's parameters, its columns or its effect is a minor version at least; and a statement removed is a minor version too, which lists it. The search index's statements are under queries/search/ on the same terms.

queries/signatures.json states the three for every statement of both directories: its name, its parameters in order of first appearance, the list slots it reads and the columns it answers, in order, each under a name of its own. It is generated from the statements (checks/signatures.py) and held to them, so a change to a statement that moves any of the three shows in that file, and one that moves none is a change of text alone.

**A statement names its columns.** No statement, canonical or an implementation's own, reads `*` or inserts without a column list, so a column a later version adds changes no statement's rows nor its effect, which is what lets a migration adding one raise no compatibility version (§6). The one exception is a program judging whether it opens a store at all (§4.2, §6 step 2): its own text MAY read `store_meta` with `*`, taking each column it knows by name, since the row it judges may be another draft's, lacking a column this draft names or holding one it does not know.

**List parameters.** A statement taking a list reads it from `temp.param(slot, position, value)`, a temporary table per connection (`create_param`), by its slot: `collections`, `links`, `hashes`, `handles`, `ids` or `flags`, as the statement names it. The caller fills it inside the statement's transaction, `clear_param` then one `bind_param` per value in order, so the text stays one for any length and under any variable limit. A value bound twice counts twice where the statement counts (`release_pins`). A read over a whole collection and the same read over the link ids a slot names are two statements, the second named `_by_link` and seeking each id, never one statement choosing between them. The table's `value` column carries no affinity, so a value is compared as bound: an SQLite without `STRICT` declares it with no type (a column declared `ANY` there takes NUMERIC affinity, and a statement joining a slot to a key column no longer seeks it). This is the canonical text's calling convention; text of an implementation's own binds its lists as it chooses.

**A flag set is written in two parts.** Its system flags are bits of the row's `marks` or `base_marks` (§13), which `insert_item`, `update_item`, `insert_binding` and `update_binding` take; its other flags are rows, written after the row by `retain_flags` and `add_flags` (or their base twins), the `flags` slot holding those alone. A writer whose set holds no other flag, a row fresh or holding none, runs neither.

**Lists as rows.** A statement reading a placement's flags or a binding's base flags answers the set as one text, `flags` or `base_flags`: the flags its bits name and its rows hold, joined with single spaces in no order, `''` known-empty, `NULL` unknown (§13). A list Annex A derives in document order (`mail_in_reply_to`, `task_category`) is read apart, by `load_in_reply_to` and `load_categories` or their `_by_link` twins, as `load_addresses_by_collection` and `load_addresses_by_link` read the addresses.

### 4.5 The change feed

`items.changed` and `collections.changed` hold the value of `store_meta.next_change` the row took when it last moved. The counter only increases and every stamp is drawn once, so no two rows share one and a page ordered by `changed` is total. `PRAGMA data_version` says that something committed; the feed says what.

Triggers in the canonical DDL draw the stamps, so no writer plumbs one. An insert takes the next stamp; an update takes one only when a column a reader can observe moved. A system flag moving moves `marks`, which a reader observes; another flag added to a placement or removed from it requests the placement's stamp. A set written again as it was stamps nothing.

A summary, address, `mail_in_reply_to` or `task_category` row has no stamp: a writer changing one under an unchanged item MUST run `stamp_item` in the same transaction, which requests a stamp the trigger then draws. A renamed collection restamps every item under its new id. A source's coverage moving restamps its collection, which a reader lists with it (§14.1).

A deleted row cannot carry a stamp, so a purged item, an evicted one (§11.3), a collected object and a deleted collection, an empty one included, count in `store_meta.purges`. So does a renamed collection (`rename_collection`): its items' keys under the old id are gone as a purged row's, and the restamp above names them under the new one alone. `load_change_cursor` answers the last stamp drawn, that count and the store's identity, `store_id` and `incarnation` (§8).

A consumer records all four, folds `list_items_changed_since` and `list_collections_changed_since` above the recorded stamp on its next look, and reconciles its keys against the store only when `purges` moved. A cursor is read before a pass and recorded after it, so a crash between the two replays and skips nothing.

**A reset.** A consumer finding another `store_id` or another `incarnation` than it recorded, or a recorded stamp above the one `load_change_cursor` answers, MUST treat what it derived as unknown: it reconciles in full, or rebuilds, from the store as it stands. A restored copy answers so (§8). A producer following a queue id it enqueued (§15.4) records the store's id and incarnation with it and checks them the same way, since a restored copy may hand the id to another row.

## 5. The blob store

Bytes live under objects/, one file per hash, at `objects/<hash[0:2]>/<hash>`: one level of shard directories, at most 1,024, each named by the first two characters of the names it holds. The name and the path are normative (§16).

- The digest is BLAKE3 at its default 32-byte output, over the raw bytes, whole. It is the only one: `store_meta.hash_algo` is `blake3`, a closed vocabulary (§13), so another algorithm would be a value a migration adds, raising `read_version` (§6).
- The name is the digest in RFC 4648 §6 base32, lowercased, unpadded: 52 characters of `a` to `z` and `2` to `7`. The schema holds `objects.hash` to that shape, and every column naming a body to it through its foreign key.
- §16's vectors are what an implementation checks itself against; the empty body is a real object.

**A name is never a path.** An implementation MUST check a name against the alphabet and the length before it builds a path from it, wherever it read the name: a row, a payload, a directory entry, a remote's answer. Where the platform allows it, it MUST NOT follow a symbolic link when it opens a shard directory or a blob (`O_NOFOLLOW`, with `O_DIRECTORY` through `openat` for the directory, or `lstat` before the open): a link found where either belongs holds no body, and an owner moves it into quarantine/ as §7 moves a body failing its name.

**Write** never replaces: a period-prefixed temporary file in the shard directory, named uniquely to the writer so two processes storing one body never share it, `fsync`, a move onto the final name that fails when the name exists, then `fsync` the directory. The move is `link(2)` of the temporary to the final name then `unlink(2)` of the temporary, on Linux `renameat2` with `RENAME_NOREPLACE`, or the platform's no-replace move (below); never `rename(2)`, which replaces. Each of these is atomic: the name appears holding the whole body or not at all.

**The directories are flushed.** A write creating its shard directory flushes objects/ too, so the new directory outlasts a power loss as the body in it does. A writer keeping a name it found held (below) flushes the shard directory all the same, before the row naming that body commits: the entry may be another writer's, moved and not flushed yet. The collector flushes every directory it unlinked in before it answers, so an erase answers only once its unlinks are durable (§11.5).

**A temporary is the store's own.** Every period-prefixed regular file under objects/, in it or in a shard directory, is a writer's temporary, whoever wrote it, and no implementation keeps another file there. A writer unlinks its own once its move is made or has failed. One a writer left behind, killed between its `link` and its `unlink` or inside an exclusive copy (below), may hold a whole body under a second name that no row names and no walk by name finds: the collector unlinks every one and reports them (below).

**An exclusive create and copy** is the one move that is not atomic, and a writer MAY use it only where no atomic no-replace move is offered or allowed (on Android before API 30, or where `renameat2` refuses `RENAME_NOREPLACE`): the final name created with `O_CREAT | O_EXCL`, which fails when the name exists, a link included; the temporary's bytes copied into it; the file `fsync`ed; then the temporary unlinked. While the copy runs, and after a crash in it, the name holds part of the body, which a read finds failing its name (§7). A copy that fails unlinks the part it created, whose bytes the temporary still holds; a part a crash left behind is set aside by the next write of that body (below).

**A name held is verified.** When the final name exists, the writer MUST verify the file already there against its name (§7) before it keeps it, and so MUST a writer that skips its write because it finds the name or its row there. A file that passes is kept and the temporary unlinked: no write replaces a body, so a file another process verified, read or pinned is never swapped under it. A file that fails holds no body and is never kept in place of the bytes in hand:

- an owner moves it into quarantine/ as §7 moves a body failing its name, holding the staging lock exclusively and serialised against its own writers, after verifying it again under the lock, then makes its move again;
- a producer, which moves nothing (§7), fails its write and enqueues nothing, reporting the name, its bytes staying with its caller until the owner frees the name (a write, a read or a collector's run of its own).

Any other failure of the move fails the write. A body streamed to its path (§14) is written the same way, named by the digest of the bytes streamed.

**Reference counting**: `objects.refcount` MUST equal the number of pointers at the hash across `items.object_hash`, `items.conflict_object`, `bindings.base_object`, `bindings.conflict_object`, `bindings.shared_object` and `queue.object_hash`, maintained in the same transaction as the writes, a producer's enqueue included (`pin_object`, §15.1).

`bindings.shared_object` is counted as `bindings.base_object` is. It names the body a binding last agreed with the shared item, the common ancestor an engine reads to merge a source's body with the item's (SYNC.md §9). It MUST therefore outlive the item's own body until every binding has reconciled against what replaced it: one body per binding, released when the binding agrees with another.

**An unreferenced object is not a deleted one.** A write MUST NOT delete a row at refcount zero nor unlink its blob: a consumer MAY index a body in one batch and attach it in a later one.

**The collector** is one operation, run when asked:

1. It MUST `recompute_refcounts` first (§7), so a count a writer left behind is settled before anything is judged by it.
2. It deletes the rows at `refcount <= 0` (`list_garbage_objects` and `delete_garbage_objects` in the reference form, §4.4).
3. It walks objects/ and unlinks every file no row names (`object_exists`, a point lookup per file), crash orphans included. Of the files named as bodies it unlinks only a regular file, read by `lstat`, whose name is well-formed and begins with the two characters naming its shard directory, itself a directory and not a link, named by two characters of the alphabet.
4. It unlinks every period-prefixed regular file it meets, in objects/ and in each shard directory, read by `lstat`: a temporary (above), which under its locks no writer is still to move. It reports each.
5. Anything else it leaves in place and reports: a link, a period-prefixed name that is no regular file, any other name. It flushes every directory it unlinked in (above). It never walks quarantine/ (§7) nor local/ (§3).

It MUST hold the owner lock and take the staging lock exclusively (§8), which proves no other process is between a body and its row, nor between a temporary and its move.

It MUST NOT run while one of the owner's own verbs is between two chunks (§14): a body streamed in one chunk and attached in the next is exactly a row no pointer names yet. Scheduling it is the owner's; a store that never collects grows without bound.

**Other platforms.** The calls above are POSIX's; on Windows and macOS they are spelled, and in part behave, otherwise:

- On Windows, the no-replace move is `MoveFileExW` without `MOVEFILE_REPLACE_EXISTING`, with `MOVEFILE_WRITE_THROUGH`, or `CreateHardLinkW` then deleting the temporary. A directory cannot be flushed as a file is, so the directory `fsync` has no equivalent there.
- On Windows, a file another process holds open is deleted only when that process opened it with `FILE_SHARE_DELETE`, and its name stays taken until the last handle closes. A reader SHOULD open a blob so; an unlink the collector cannot make is left for the next collection, the row being gone already, and a write meeting a name still taken fails and is tried again, as any other failure of the move. A move into quarantine/ that fails is made by the next read finding the mismatch (§7).
- On macOS, `fsync` stops at the drive's cache: the temporary file and the directory are flushed with `fcntl` and `F_FULLFSYNC`. The no-replace move is `renamex_np` with `RENAME_EXCL`, or `link(2)` as above.

*Note:* On Android, the platform's SELinux policy denies `link(2)` to an app on the files of its own data directory, so the no-replace move there is `renameat2` with `RENAME_NOREPLACE` from API 30, and the exclusive create and copy (above) before it, where the C library exports no `renameat2` and the app's system call filter, built from the C library's calls, may end the process (`SIGSYS`) on a raw one rather than refuse it; it is the copy too wherever `renameat2` answers `ENOSYS` or `EINVAL`.

## 6. Migrations

Schema evolution is ordered, forward-only SQL under migrations/storage/, named NNNN_description.sql, NNNN the version it brings a store to. Version 1 is 0001_init.sql; once released it never changes, and every later change to the schema (a table, a column, an index, a trigger or a constraint) is a migration to the next version.

**What a migration raises.** Each migration states the compatibility versions it raises (§4.2), each to its own number, `version` being raised by every one:

- neither, for an index, a table, or a column a reader may ignore: nullable, or `NOT NULL` with a default;
- `read_version`, for a renamed or dropped column or a changed meaning: a value added to a closed vocabulary (§13), a column read otherwise than before;
- `produce_version`, for a `NOT NULL` column without a default on a table producers write (`queue`, `objects`, `collections`), or a new rule on what a producer enqueues (§15).

An added column raises neither only because every statement names its columns (§4.4).

An owner opening a store runs these steps in order, and nothing else changes the schema:

1. Read `PRAGMA user_version`, `0` for a fresh database, which goes to step 3.
2. Read `load_store_meta`. A store §4.2 says the program does not open MUST be refused, naming both versions: a draft's store under another draft or a release, a store lacking `format_version`, a released store above the highest version the implementation knows. So MUST a store whose `hash_algo` the implementation does not know, naming it (§7). It is never reconciled, migrated, rebuilt nor written, whatever the profile opening it.
3. For each migration above the store's version, in order: open a transaction, run the script, set `user_version` and, through `set_store_version`, the three versions the migration states, commit. A failed script rolls back and stops, the store left at the last version committed. A fresh database runs `init_store_meta` in the transaction applying 0001_init.sql, so the row a later migration stamps exists. A migration rebuilding a table, or editing a `CHECK`, is run as the two paragraphs below say.

**A migration that rebuilds a table.** SQLite changes a table's constraints, and on the SQLite floor (§4.1) drops or renames a column, only by a rebuild: a new table created, the rows copied, the old table dropped, the new one renamed to its name. With foreign keys on, dropping a table deletes its rows first, and every row referencing them goes or is nulled by its `ON DELETE` action, in that transaction and with no error. A rebuild MUST NOT run in one transaction with foreign keys on, as step 3 runs any other migration: on the floor it commits with every referencing row gone, `PRAGMA integrity_check` clean. A migration states that it rebuilds, and then:

- the runner sets `PRAGMA foreign_keys = OFF` before it opens the transaction, the pragma changing nothing inside one, and `ON` again once the transaction has ended, committed or rolled back;
- the script creates the new table under a temporary name, with every column, constraint and `WITHOUT ROWID` clause of the old one but what the migration changes, copies the rows by named columns (§4.4), drops the old table and renames the new one to its name, in that order, so every reference another table makes keeps naming it;
- the script creates again every index and every trigger of the table, which the drop took, and drops before the rebuild, then creates again after it, every trigger and view of another table whose text names the table: a current SQLite refuses the rename while the schema names a table that is gone;
- the script keeps the table's row of `sqlite_sequence` where the table is declared `AUTOINCREMENT` (`items`, `queue`), read before the drop and written back after the rename, so no placement id and no queue id is handed out twice (§4.3, §15);
- the runner reads `PRAGMA foreign_key_check` before the commit, which MUST answer no row, and `PRAGMA integrity_check`, which MUST answer `ok`; any other answer rolls the migration back.

**A closed vocabulary grows by its `CHECK`.** A migration adding a value to a closed vocabulary (§13) need not rebuild: it MAY edit the constraint in the table's stored text, in the migration's transaction and with foreign keys on, under `PRAGMA writable_schema = ON`, replacing the `CHECK`'s text exactly and nothing else, then raising `PRAGMA schema_version` and setting `writable_schema` off, the runner reading `PRAGMA integrity_check` before the commit as above. Every row and every other schema object stays as it was. SQLite refuses that edit on a connection in defensive mode (§18), so the runner applies such a migration with the connection out of it, for that transaction alone.

There are no down-migrations, and no implementation rebuilds a store it cannot read: it refuses it (step 2), and a corrupt one is repaired (§7) or refused. A migration MUST preserve every row of every table and the meaning of every column it keeps: the queue, the receipts, the references, the capabilities, the performers, the retained rows and the collections no source syncs hold state no source restores.

A **reader** or a **producer** never changes the schema: it runs step 2 under its own profile's terms (§4.2), and opens any store it does not refuse as it stands.

**pimdir.db holds the canonical schema alone.** An implementation keeps state of its own outside pimdir.db, under local/ (§3) or outside the store directory, and a newer owner adds to the schema only through a migration to a later version, which an older owner refuses (step 2).

**Derivations are revised.** Annex A carries a revision, and `store_meta.derivation` the one a store's summaries, addresses and sort keys stand under, written by `init_store_meta` as the creator's.

An owner at a later revision than the store's MUST re-derive, from every held body, the columns the revisions between them changed, paging the held bodies (`list_held_mail`, `list_held_tasks`). It records its own revision with `set_derivation` in the transaction writing the last page. Until it is recorded the re-derivation is owed, and the next open of such an owner resumes it.

An owner at an earlier revision than the store's derives as it knows, and MUST record its own revision with `set_derivation` in the transaction of its first write of a summary, an address or a sort key: the store's rows then stand under the earlier revision, and the next owner at a later one re-derives them.

## 7. Integrity

- A store is self-checking: `PRAGMA integrity_check`, plus recomputing an object's hash against its row and file name.
- The refcount invariant (§5) and the foreign keys are the structural invariants. `recompute_refcounts` settles every object in one grouped pass over the six pointer columns, linear in the pointers, counting zero for an object nothing names.
- `objects.refcount` carries `CHECK (refcount >= 0)`, checked per statement, so a double release fails at the release.
- **A body is checked against its name when read.** Whoever reads a body whole (a reader, a producer, an owner, an engine, an indexer, a performer) MUST verify that its bytes hash to its name before it serves, parses, indexes, pushes or copies it, or performs an intent with it. A streamed read verifies at the end of the stream and fails it on a mismatch, before its consumer commits anything built from it: a push or a submission is aborted, a parse or an index discarded.
- **A range is verified by a whole read.** Whoever serves, parses or copies part of a body (an attachment opened by offset, a message's head) MUST first read the whole file through the descriptor it reads the part from, and verify it. That verification covers every range read through the descriptor while it stays open; none is recorded, so the next open verifies again.
- **Failing is missing.** A body whose bytes do not hash to its name and one whose file is missing are the same state: the item holds no body. Such content is never served, parsed, indexed, pushed nor used to perform an intent: an `add` or an `update` carrying it is retried, then parked (§15.2), and the next `Full` upgrade of an item holding it fetches it again where a source holds it (SYNC.md §6).
- **A mismatch is quarantined, never unlinked.** An owner finding a body that fails its name MUST move the file out of objects/ into quarantine/ (§3), under its name, a period and a suffix unique to the move, so one quarantined file never replaces another, and report it. It MUST NOT unlink it: the bytes may be the only copy of something a person can still recover. It moves it holding the staging lock exclusively (§8) and serialised against its own writers, as the collector is, after verifying the file again under the lock. The row stays, and the name being free, the next write of that body lands. An owner's write finding the name held by such a file moves it so before it writes again (§5).
- A reader or a producer finding a mismatch moves nothing: it treats the body as missing and reports it, a producer's write meeting one under the name it writes failing (§5). No program reads a file under quarantine/ as a body, the collector never walks it, and only the user empties it, through an operation the implementation offers.
- An engine MUST NOT push a body it has not verified in the run: a create or an edit whose body fails stays pending and is reported.
- **An unknown algorithm is no corruption.** A program finding a `store_meta.hash_algo` it does not know refuses the store (§6 step 2): it never verifies, quarantines, collects nor fetches again a body by a name read under another algorithm.
- The order of trust is blob bytes over database row, a name over bytes: a row whose size disagrees with a body hashing to its name is repaired from the body; bytes that do not hash to their name are no body at all.

## 8. Concurrency and ownership

At most one process on one host owns pimdir.db at a time, and only the owner mutates collections, items, bindings, sources, capabilities, performers and objects, the §15 enqueue excepted.

An owner MUST hold an exclusive advisory lock on owner.lock for as long as it owns the store. The lock belongs to the open file, so a crashed owner leaves nothing to recover. An owner that cannot take it MUST fail immediately, naming the store, and never wait: what to do next is the caller's. The database's busy timeout is unaffected.

**A lock file stays.** A lock file, once created, MUST NOT be removed, renamed nor replaced while the store exists, by any program: a lock belongs to the open file, so a process opening a new file at the path would take a lock the holder of the old one does not exclude, and two owners would write one store. An owner SHOULD verify, before each write transaction, that the file it holds locked is still the one at the path (on Unix, `fstat` on its descriptor and `stat` on the path answering one device and one inode), and give up the store, writing nothing more, when it is not.

Every lock this standard names (owner.lock and objects.lock here, index.lock in SEARCH.md) MUST be taken whole-file on the open file:

- on Unix, with `flock(2)`: `LOCK_EX` exclusive or `LOCK_SH` shared, `LOCK_NB` added where a rule forbids waiting;
- on Windows, with `LockFileEx` over the whole range (offset 0, both length words `0xFFFFFFFF`): `LOCKFILE_EXCLUSIVE_LOCK` for exclusive, `LOCKFILE_FAIL_IMMEDIATELY` added where a rule forbids waiting.

An implementation MUST NOT use `fcntl` or `lockf` record locks for them: on Linux those do not see a `flock` lock, and a process loses them when it closes any descriptor of the file.

**Other platforms.** On Windows, the system releases the locks of a process that ended holding them when it gets to it, not at once: an owner restarted right after a crash may find owner.lock still held and fail as above, and takes it when the caller tries again. On macOS, `fsync` stops at the drive's cache, and so does SQLite's own sync under §4.1's `synchronous` unless `PRAGMA fullfsync = ON` is set, which an owner and a producer there SHOULD set; blobs are flushed as §5 says.

The rule is about processes: one owner opening several handles takes the lock once and shares it. The lock excludes other processes and nothing inside its own, so an owner MUST serialise its own collector against its own writers, and MUST release and retake the role as one operation, or it locks itself out.

Two lesser roles exist, both local-host only:

- **Readers** open read-only and see consistent WAL snapshots, any number at once, while an owner runs. A reader MUST NOT take either lock.
- **Producers** perform the §15 enqueue transaction and nothing else, and MUST NOT assume when the owner applies it. A producer MUST hold the staging lock on objects.lock shared across the blob write and the enqueue that pins it: that is the window a collector must not run inside. It holds it so across any `store_object` or `pin_object`, whether or not it wrote the blob, and across the verification of a body it names without writing (§5), until the transaction naming that body has committed: a row it creates or pins is then never one the collector is deleting, and a file it verified never one the collector unlinks before its pin lands.

On a network filesystem neither SQLite's locking nor advisory locks are reliable. Such a store MUST be owned by exactly one process on one host, SHOULD be enforced single-instance with a lease, and MUST use rollback-journal mode or `PRAGMA locking_mode = EXCLUSIVE`, never WAL's shared memory or `mmap`.

**Copies.** A backup MUST copy pimdir.db consistently, through SQLite's online backup API or `VACUUM INTO`, never as a file under a running owner, and then objects/ and quarantine/, whose files may be the only copy of a body (§7), and local/ (§3), holding the staging lock shared across the copies, though it writes nothing, so no collector unlinks a body the copied database names (§5). It copies no temporary (§5), a writer's unfinished file being no body, and neither a lock file nor index.db.

A restore puts them back with no program holding the store: it holds owner.lock as an owner does, failing at once when another holds it, and the staging lock exclusively, so no producer stages a body under it. Where a store is there it replaces it, in this way:

- **Bodies are merged.** Every file of the copy's objects/ and quarantine/ is put in under its name. A name the store already holds keeps the file it has, a file being never replaced (§5). A body the replaced store alone named stays where it is, an orphan the collector removes once it runs (§5): a restore unlinks no body.
- **The database never takes its name under the copy's incarnation**: `raise_incarnation` runs on the copy first, given the replaced store's `incarnation` when that store can still be read.
- **The store found stands until the copy is ready.** The replaced database, with its WAL, shared-memory file and journal, is removed only once every body is in and the copy's incarnation is raised. Only then is local/ replaced whole by the copy's, the owner's state being one with the database it was copied beside, and the copy becomes pimdir.db last. No owner holds a file under local/ while the restore holds owner.lock, a lock of its own included.
- **A restore stopped is run again.** Stopped before the replaced database is removed, it leaves the store it found, its database and its local/ as they stood, beside bodies put in. Stopped after, it leaves a directory holding no pimdir.db, which no program opens as a store. Neither is a store holding the database of one and the local/ of the other.
- **The journal mode** of the restored database is that of the store it replaces and, replacing none, the one an owner creates a store in (§4.1, and above on a network filesystem): a copy made by `VACUUM INTO` carries no WAL mode of its own.
- **The lock files and index.db stay** as they are. A lock file is never replaced (above), and an indexer finding another incarnation rebuilds its index (SEARCH.md §2).

The restored store keeps its `store_id` and answers an incarnation no consumer of it recorded (§4.5). The statement raises it by a random stride above both, so two restores of one backup answer two incarnations even when neither could read the store it replaced; an incarnation is compared for equality, and its size says nothing.

A live store MUST NOT be replicated by a file-synchronisation tool: each host would hold an owner lock of its own over its own copy, and the tool would copy the database and its WAL mid-write. Several devices share what a store holds through sources (SYNC.md), each with a store of its own.

## 9. Identity and dedup

Four identifiers, kept distinct:

- **handle**: the backend's per-collection id, never the cross-collection key.
- **link id**: the item's key in its collection (`items.link_id`), internal: a consumer keys reads and edits by `seq`.
- **hash**: content state and blob key.
- **seq**: the store-global public id (§9.1).

Annex A derives the **hint**; this section assigns the key. A hint is usable when it is not empty once trimmed of the space (U+0020) and the tab (U+0009), no other character counting as whitespace here; content stating none, or one that is not usable (an empty `UID`, one of spaces alone), takes the kind's fallback in its place (`alt:` for a message, `hash:` for a DAV resource). A usable hint is the key verbatim, the trim judging it and never changing it. The hint or the fallback, escaped as below, is the key `k` a writer assigns from.

**Reserved prefixes.** `alt:`, `hash:`, `dup:`, `part:` and `file:` begin the keys a writer derives (below, Annex A.7), and `esc:` the escape. A hint beginning with any of the six, compared byte for byte, MUST be escaped before the table below: the key is `esc:` followed by the hint (`esc:hash:0123`).

The escaped key is the item's link id like any other, minted over as any other (`dup:esc:hash:0123#7`). A connector naming the identity to its server strips the one leading `esc:`.

**Held.** A key is **held** in a collection when a row of `items` there has it, whatever the row's state: live, a tombstone, or retained (§11), so `seq_by_link` answers for it. It is **free** otherwise.

**Minting.** The key **minted** over a key and a handle is `dup:`, the key, `#` and the handle, concatenated verbatim (`dup:abc@host#1174`, `dup:alt:Alert|2026-08-01T10:00:00Z|cron@host#1175`). A minted key that is held is **minted again** over the same handle, as often as it takes to reach a free key (`dup:dup:abc@host#1174#1174`). Minting yields a free key, and never lands, joins nor revives a row holding the key it would mint.

**Assigning the key.** A writer naming a member a source lists or fetches (SYNC.md §6), or staging a create (SYNC.md §7), MUST take its `link_id` from the first row of this table that matches what holds `k` in the collection. A member is minted over its handle, a create over the provisional handle it derives (§2). A handle the source already binds is no member to name: its key was resolved once (SYNC.md §6), and a `hash:` key changing under it retires its binding (§10).

**Agreeing.** A row holding a message **agrees** with the member, the `Add` or the create being keyed when their summaries agree on `subject`, `date` and `sender` (Annex A.1), compared byte for byte, `NULL` matching `NULL`, and, for a retained row, on `size` too where both state one: no source holds a retained message any more, and reviving it makes its body the member's unread, as linking does (SYNC.md §6). A row of another kind agrees with anything. A message that does not agree is another one reusing the `Message-ID`, and is never joined, landed nor revived: one body would stand for two messages.

The three are compared as they stand in the two summaries, whatever read them. Annex A.1 derives each from the raw field, and two derivations of one message agree; a value a source decoded by rules of its own may differ from it, so a connector reads the three raw wherever its source serves them (Annex A.1; SYNC.md §4), and a member named from a decoded value that differs is kept apart from its own message, a missed dedup, never a wrong merge.

**Across collections.** The same agreement guards a hint between the collections of an account, where the table below assigns nothing: a `Message-ID` two mailboxes hold names one message only where the two rows agree. Three rules read it, each for a message alone, a row of another kind agreeing with anything:

- a body is linked from a row of another collection only when that row agrees with the placement, and on `size` too where the placement states one (`lookup_objects`, SYNC.md §6);
- a message shares the `seq` of a row holding its key in another collection only when it agrees with that row, and draws its own otherwise (§9.1);
- a retiring row holding no body is held elsewhere, and purged for it, only by a row that agrees with it (§11.1).

The last two compare `subject`, `date` and `sender` alone, no body being adopted, so a `size` the row or the message leaves `NULL`, or states as an estimate, plays no part. A row holding no summary agrees with no message. A message disagreeing with the row another collection holds keeps the bare key in its own collection, where the key is free, fetches its own body and shows as an item of its own.

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

Two keys are assigned outside the table. A body kept apart by a policy, an overruling `Edit` or a revive (§11, §11.1) is keyed by minting over the handle of the binding that settled it, `k` being held by the item it lost to, so a second body kept through one binding is minted again beside the first. A rekey carries each key by link id (SYNC.md §8).

A fallback goes through the same table: two messages stating no `Message-ID` may share an `alt:` key, two byte-identical UID-less resources one `hash:` key, and the second of each is a row the collection holds.

The minted form is deterministic and prefixed like the fallbacks, so a prefixed id is never pushed as a protocol identity. It is opaque: a reader MUST NOT parse it and a store MUST NOT rewrite it, since rewriting would change a `seq` a consumer has shown.

Deduplication keys on **hash**: one body in two collections is stored once. Merging keys on the **hint**, conservatively: a missed dedup is harmless, a wrong merge hides data. `lookup_objects` (§14) is keyed on the assigned link id, so a minted item fetches its own body.

A writer-derived key (`alt:`, `hash:`, `dup:`) carries no identity: two messages with equal subject, date and sender and no `Message-ID` share an `alt:` key and may be two bodies. Such a key MUST NOT match in `lookup_objects` and MUST NOT share a `seq` (§9.1), and no reference names one (§14.2), nor a file of a part of a message under one (§14.3).

A `hash:` key names bytes, so a UID-less card edited on its server changes key under the same handle: the old item is retained, the new one is ordinary, and every other source sees a delete and an add (SYNC.md §3).

All four are store-wide, accounts included (§9.2). An identity or a body in more than one collection is a fact the store reports (`list_link_placements`, `list_object_placements`), never a merge it performs.

### 9.1 The public id (`seq`)

`items.seq` is a small integer a consumer shows and accepts wherever it would take a link id. One `link_id` keeps one `seq` in every collection and account of one kind it is filed in, a message's only among the rows that agree with it (§9), drawn from `store_meta.next_seq` (`seq_for_link_any`, else `bump_next_seq`). It is assigned once, only increases, and is never reused. A consumer reads and edits by `(collection, seq)`, which is unique.

The kind is part of the identity, as for a reference (§14.2): a message whose `Message-ID` spells an event's `UID` is another item, and draws its own `seq`. `seq_for_link_any(collection, link_id, subject, date, sender)` answers the `seq` of a row holding the link id in a collection of the kind of `collection`, whatever its state, so a retained row's `seq` is shared too.

For a message it answers only a row agreeing with the `subject`, `date` and `sender` of the summary being written, `NULL` matching `NULL`, the lowest `seq` when rows that agree hold several: a message reusing a `Message-ID` another mailbox holds is another message there too, and one hit apart in a merged view. A row holding no summary agrees with none. The three are read for mail alone and bound `NULL` for another kind. A `seq` is drawn when the item is named and never moves, so a row whose summary is restated later keeps the one it drew.

A minted key, an `alt:` key and a `hash:` key each draw their own `seq`: a derived key restates nothing the content carries, and `seq_for_link_any` is run for none. The item holding the bare hint keeps the shared one, so one message in two mailboxes shows once and two resources one collection holds show twice.

A file's `part:` or `file:` key (Annex A.7) is a name the store gives, not a guess at one, and shares its `seq` as a hint does, so a file in two folders shows once. A `part:` key is only ever built over a message's identity, never over a derived key (§14.3).

### 9.2 Accounts

`collections.account` is a grouping key, `NULL` in a single-account store. `collections.id` stays unique store-wide, so an owner filing two accounts namespaces their ids (`work/INBOX`), records the account so a reader filters on a column rather than a prefix, and records the bare name in `name` (§14) so a reader renders it without parsing one.

The account scopes nothing: link ids, hashes and `seq`s keep their store-wide meaning. What multiplicity across accounts means is the interface's: a mail view lists the placements, a contact view may offer a merge.

Ownership (§8) and sources (§10) are unchanged, so an owner syncing accounts in parallel processes MUST give each its own store. A `link_id` collision between unrelated servers is answered by conservative merging: a consumer that cannot tolerate a false pairing compares bodies.

The store records nothing else about an account: no credentials (§18), no endpoints. It learns an account from its collections, so an account with none is not listed. An owner that namespaces MUST keep the separator out of account ids, since `a` with `b/c` and `a/b` with `c` spell the same string, and SHOULD choose an id that never changes.

### 9.3 The sort key

`items.sort_key` is one TEXT column giving an item's position in its collection's natural order, since neither a link id nor a `seq` is an order.

- The store defines the column, the ordering and the paging; Annex A defines what a key holds per kind.
- It is **written, never derived**: the store MUST NOT parse a summary to obtain it.
- Byte order is the order (`BINARY` collation), so a timestamp is RFC 3339 UTC at fixed width with the `Z` designator.
- `''` means unknown, the default: last in a descending listing, first in an ascending one.
- `seq` breaks ties, so a page over `(sort_key, seq)` is total.
- `set_sort_key` restates a key without refetching; a `write` MUST leave an existing key alone unless it carries a new one.

Paging is a seek on `items_by_sort`, not a scan, and costs the same at any depth. A keyset statement bounds the index by its cursor itself: a `NULL` cursor, the first page in every paged read (§14.1), is coalesced to a bound beyond every key (the empty blob, which sorts above every text, newest first; the empty text and `seq` 0 oldest first) and never tested apart, since `:after_key IS NULL OR …` keeps the cursor out of the index and walks every row above it.

A page over a set of collections (`list_mail_page_filtered`, `search_mail`, `search_contacts`, `search_calendar`, `search_files`) is a **merge**: each collection of the set seeks its own `items_by_sort` beyond the cursor and answers at most the page under the page's filters, and their union, at most the set's size times the page, is ordered on `(sort_key, seq, collection)` and cut. A page never reads another collection's rows nor another kind's, and a collection named twice in the set is read once. A filter one collection matches seldom reads that collection down to the rows it matches, or whole. A substituted statement SHOULD keep both plans.

A key is presentation, not sync: a wrong one mis-sorts and loses nothing.

## 10. Sync model

A shared item holds the merged truth; a binding per source records the base last agreed with that source. The sync part (SYNC.md) derives what changed on each side and reconciles.

A binding records two agreement points and a store MUST keep both:

- `base_object`, what the source last agreed with its remote, moved only by a sync, so a pending push stays derivable;
- `shared_object`, what it last agreed with the shared item: moved by an absorbed upsert carrying a body and leaving the item unconflicted, never by a pull carrying none (SYNC.md §9), and pinned (§5) so the merge can read it.

`level` is the tier an item reached, a claim; `object_hash IS NOT NULL` is the fact of a body. A remote content change drops the body while the level stays; a release (§11.4) drops both. `deleted` carries a removal until every source has dropped it, and the item is then retained (§11).

Nothing reaches the store unnamed: a member a source lists arrives with its identity and summary (SYNC.md §4) and becomes an item and a binding in the write of the page that lists it.

**Coverage and rounds.** A source syncing a mail collection under a scope lists it in rounds (SYNC.md §5):

- `open_round` draws the round's id and records its scope and whether it is a band round, in the write of its first page.
- Every page stamps the bindings of the handles it listed with that id (`stamp_bindings`) and records its resume cursor and any checkpoint it carries (`set_round_cursor`).
- A head (SYNC.md §5) lands in a write of its own. A delta head stamps the handles it listed (`stamp_bindings`) and records the checkpoint it carries with no cursor, which keeps the cursor a page landed (`set_round_cursor`). A band head records neither.
- The last page reads the members it found absent (`list_unstamped_bindings`): the based bindings the round did not stamp, under a handle that is not provisional (a delivered create, SYNC.md §5), whose item's `date` falls in its scope, or is unknown and the round is no band round. A listing a date filter narrowed (`:narrowed` 1, SYNC.md §4) proves the absence of a member only when an unfiltered enumeration of the collection's handles, bound in the `handles` slot (`:enumerated` 1), lacks it, whatever its date, and of none when the round hands no enumeration.
- `close_round` lands the round's checkpoint, records the coverage and clears the round, in the write after the last chunk.

A round is never closed by a rebuild: a rekey lands its checkpoint and leaves the coverage alone. A scope narrowing inside the coverage is recorded with `set_coverage`, `covered_at` unchanged. A coverage moving restamps its collection (§4.5), since a reader lists it with the collection.

Two divergences are recorded and are not the same fact: `items.conflicted` and `items.conflict_object`, two sources editing the shared body differently; `bindings.conflicted`, `conflict_revision` and `conflict_object`, one source diverging from its own remote. A store MUST persist both independently, and the schema holds that neither carries a diverging body without its flag.

A binding's conflict MUST be cleared when the sync writes any resolved state for it, releasing the pin its `conflict_object` held.

An item's conflict MUST be cleared, releasing its pin the same way, by:

- the write that adopts a body for it (an `Edit`, SYNC.md §7, or an upsert the collection's policy lets through);
- the upgrade that fetches, under a `prefer-` policy, the incoming body a divergence was recorded without (SYNC.md §6), or the write filling, under one, an item whose own body it was recorded without (SYNC.md §9), whichever body that policy keeps.

A write filling an item a pull emptied (SYNC.md §9) adopts a body and, under `manual`, leaves the conflict standing. While it stands, every binding of the item projects `Conflict` but on a deleted item, where it projects a `Tombstone` (SYNC.md §3), so no source pushes the disputed body over another. `list_conflicted_items` lists what awaits a decision.

A write resolving an existing `(collection, link_id, source)` binding to a different handle MUST be refused, recording no trace of the incoming handle. A rebind is licensed only by a drop of the bound handle in the same batch, with reason `Superseded` (a provisional handle an accepted add replaced) or `Rekeyed` (§12).

A source holding one identity twice never reaches the refusal: the second copy resolves to a minted key (§9) and is stored as an item beside the first. Two items is the report; the store picks no survivor and warns about nothing.

The other direction is a rebind too: a handle names one link id per source. A write resolving a bound handle to a different link id, a `hash:` key that changed under the same DAV resource (§9), MUST retire the old binding first, in the same transaction, as a `Deleted` drop of that handle would (§11).

The unique index on `(collection, source, handle)` refuses a write that does not.

## 11. Retention

When an item's last binding vanishes the store MUST retain the row rather than delete it. Only an explicit purge removes it, or the owner's manual eviction of what lies below a date (§11.3), so a remote expunge never destroys the local copy.

The one exception is an identity another collection of the same account holds live with the same body: the item moved, or was filed twice, and nothing is lost by purging the row in the same transaction, the holder pinning the body. A holder carrying another body, or none, is not that case and the row is retained. A retiring row holding no body loses none, and is purged for any live holder, a message only for a holder that agrees with it (§9): another message reusing its `Message-ID` in another mailbox holds nothing of it, and the row is retained.

Retention is the terminal state of `deleted`: a retained row carries `deleted = 1`, no bindings, and a non-`NULL` `retained_at`, which the schema holds. It is unconditional; how long to keep and when to sweep is the owner's schedule.

A tombstone a source still binds, because that source may not remove it (SYNC.md §5), never reaches retention: it stays `deleted = 1` with its binding, hidden from the live reads and listed in the trash beside the retained rows, so nothing the user deleted is invisible.

A body a merge does not adopt (SYNC.md §5, §9), one an overruling `Edit` settles away (SYNC.md §7), or the retained body of a mutable item a bodiless placement revives (§11.1), is retained the same way, as an item of its own:

- inserted beside the item it lost to, under the key minted over the handle of the binding whose upsert, upgrade, overruling `Edit` or revive settled it, minted again over a held key (§9), so every body one binding loses is kept, the second beside the first;
- holding that body, its summary and addresses derived under Annex A, and a `seq` of its own (§9.1);
- retained at once (`retain_item`, `retained_by` that binding's source) in the write that settled it.

It has no binding, so no source is offered it. The trash view lists it, and a purge removes it as it does any retained row.

### 11.1 Requirements

- **Retire, do not delete** (`retain_item`): a writer MUST stamp `retained_at` and `retained_by` and keep `object_hash`, so the body stays pinned.
- **A held identity is not kept twice**: when another collection of the same account holds the link id live with the retiring body, or the retiring row has none and, for a message, the holder agrees with it on `subject`, `date` and `sender` (§9; `held_elsewhere`, bound to the retiring `object_hash`, which reads both rows' summaries itself), `retain_item` is followed by `purge_item` on the seq `retained_item` gives and `release_pins`, in the same transaction, and the purge counts (§4.5). A holder of the retiring body is of any kind: one link id over one body is the same bytes whatever collection holds them, so the kinds are not compared there.
- **Stamped by SQLite**: `retained_at` is written by the statement, in the shape the schema holds (§13); the cutoff of a purge is the caller's parameter.
- **Hidden from the sync seam**: `load_items` MUST filter on `retained_at IS NULL`, or the next run re-uploads every retained row.
- **Hidden from the reads**: a deleted row MUST be read as a tombstone under §14.1's live-only rule; `list_retained_page` and `count_retained` are the trash view and list every deleted row, `retained_at` saying whether a source still binds it.
- **Purge is the only true delete** of a retained row, as the owner's eviction is of a live one (§11.3), and §11.5 erases what it leaves in the files: `purge_item` and `purge_retained_before`, both guarded on `retained_at IS NOT NULL`, both `RETURN` the pinned hashes for `release_pins` in the same transaction. The bodies fall to the collector. A tombstone a source still binds is not purgeable: its source has not agreed.
- **A reappearing link id revives** (`retained_item` then `revive_item`), as §9's table says: stamps cleared, `deleted` back to 0, `seq` kept. One branch serves a source-side resurrection and a queued `add`. Minting never revives a row (§9).
- **A revive adopts the incoming body when there is one.** When the incoming placement carries none (a `Meta` listing or fetch, a `Copy` or `Move` with no body):
  - for an immutable kind the retained body stays and becomes the binding's base, so a restore costs no network, the row agreeing with the member on its size as §9 requires;
  - for a mutable kind the retained body is no longer the item's: the revived item holds no body, at `Meta`, for the next `Full` upgrade to fetch, and the retained body is kept as a retained item of its own, as a body a policy overrules is (§11), keyed over the reviving binding's handle and reported where a run reports one (SYNC.md §5). The member's revision names the body its server holds now, which may not be the one the row held when it was retired, so keeping that one as the item's would read as a local edit and be pushed over it.

  The pins the retained row held are released only for what the revive replaced.
- `retained_by` is diagnostic; a retained item has no binding and pushes nothing.

### 11.2 Purging

`purge_item(collection, seq)` empties one item; `purge_retained_before(before)` every item retired before an RFC 3339 instant, its cutoff `before`, store-wide, the owner computing the cutoff from its own policy. A cutoff of now reproduces terminal deletion. `retained_bytes()` reports what retention holds. `purge_retained_before` and `retained_bytes` read the retained rows alone, on `items_by_retained`, so a sweep reads what it purges however large the store. Either purge counts in `store_meta.purges` through the delete trigger (§4.5).

The comparison is textual, so a cutoff MUST be written as the stamps are, with milliseconds and the `Z` designator (`%Y-%m-%dT%H:%M:%fZ`). A cutoff without milliseconds sorts after every stamp of its own second and purges up to a second more than asked.

### 11.3 Evicting below a date

Nothing in pimdir is deleted by inference, and a scope is no exception: mail older than a source's scope stays stored and readable, and a sync neither drops it nor pushes anything for it (SYNC.md §5).

Freeing that space is the owner's, on the user's request, by an **eviction**, **`evict_before(collection, before)`**: every live mail item of the collection whose `date` is older than the RFC 3339 instant `before` and that owes nothing is removed with its bindings, summary and addresses. An item with no `date` is never older.

An item owes something, and stays, while:

- it has no binding: no source holds it, so no relisting restores it (a copy kept on the device);
- it is conflicted, or a binding of it is conflicted or has no base;
- a binding of it is a delivered create's, based under a provisional handle (§2): no listing has named its member yet, and the flags, the body or the delete staged on it are owed to the page that lands it (SYNC.md §5);
- its flags differ from a binding's base flags, both known, by a system flag or by a flag either set holds and the other lacks;
- a person's reference names it (§14.2), which no relisting restores.

An eviction is not a delete: it stamps no tombstone, queues nothing and derives no push, and the remote keeps every member, which a later widening lists and names again.

It MUST run in one transaction with `recompute_refcounts`, the cascade dropping pins no statement returns; the bodies fall to the collector, and each row counts in `store_meta.purges` (§4.5). It MUST NOT run between two chunks of a verb (§5).

An owner SHOULD drain the queue first, an action addressing an evicted item by `seq` being parked. An owner narrowing a scope and evicting below it records the narrower coverage with the next sync (SYNC.md §5), not before.

### 11.4 Releasing bodies below a date

An owner keeping the headers of a mail collection and only some of its bodies frees the others by **`release_before(collections, before)`**. Every live mail item of a set of collections whose `sort_key` lies below `before` (an RFC 3339 instant, or `NULL` for no ceiling, the undated below any) and that holds a body it does not need goes back to `Meta`:

- `object_hash` is cleared and `level` set to `1`;
- the summary, the addresses, the flags, the bindings and `seq` stay, so the item is still listed, counted and searched;
- a binding whose `base_object` is the item's body releases it too (`release_bases_before`) and stays based, `base_present` saying so alone (§13): one identity is one message, so the base an immutable kind keeps is that body and nothing else.

An item needs its body, and keeps it, while:

- it is conflicted, or a binding of it is conflicted;
- a binding of it has no base (a pending create) or holds another body as its base (a local edit);
- it has no binding;
- a source of the collection (`sources`) binds it not, the body being what propagation offers that source (SYNC.md §9).

An unpushed flag needs no body and does not hold one back. A source declared for the account but not synced on the collection yet holds nothing back, having no `sources` row there: an owner adding a mirror syncs it once before a release. Undated mail lies below any ceiling and is released with the rest.

A released body is fetched again by the next `Full` upgrade, linked from another collection holding it when it can be (SYNC.md §6). A released row is no claim: a sync names it at `Meta` and fetches nothing.

A release is no delete and no eviction: it stamps no tombstone, queues nothing, derives no push, and the remote keeps every body.

`release_bases_before` then `release_before` MUST run in one transaction with `recompute_refcounts`, in that order, the first leaving true what the second selects. Each released item is restamped (§4.5). The bodies fall to the collector, unless another collection or a queued action still pins them. It MUST NOT run between two chunks of a verb (§5).

### 11.5 Erasing

A purge removes a row from the store's tables, not its bytes from the store's files: SQLite leaves what a delete frees in the file and in the WAL, FTS5 keeps a deleted row's tokens in its segments until they merge, and the collector unlinks a body only once no row names it.

Every connection writing pimdir.db or index.db MUST set `PRAGMA secure_delete = ON`, so the pages and the cells a delete frees are zeroed as they are freed. An owner erasing an item, at the user's request, runs in order:

1. its purge (§11.2), once it is retained, or `delete_unbound_item` for one no source binds (§14.3), the pins released in the same transaction;
2. the collector (§5), which unlinks every body no row names any more and every temporary a writer left behind, and flushes the directories it unlinked in before it answers;
3. where an index is kept, a refresh deleting the item's placement, its bodies and the thread rows it gave (SEARCH.md §4, §9), then `optimize_text`;
4. `PRAGMA wal_checkpoint(TRUNCATE)` on pimdir.db and index.db, again until it reports every frame checkpointed.

The item's bytes are then in neither database nor in objects/, under a body's name or a temporary's, unless another item names the same body. A backup, quarantine/ (§7) and the filesystem's own copies (free blocks, snapshots) are beyond the store's reach (§18).

## 12. Collection generation

`collections.generation` is the handle-space epoch. The owner MUST bump it (`bump_generation`) in the transaction of the rebuild that re-learns a collection's handles (an IMAP `UIDVALIDITY` change), and readers deriving epoch-dependent protocol values read it with `load_generation`. Ordinary syncs, full resyncs and content changes MUST NOT bump it.

A rebuild's batch drops the old spine and upserts the same items under their new handles, so a binding's handle does move. What licenses it is the drop with reason `Rekeyed` (§14), per handle; a duplicate in the same batch is still refused. The batch carries no op for the bump: a `Rekeyed` drop is what tells the store the batch is a rebuild, and the store bumps in the transaction applying it.

## 13. Encodings

Two implementations produce byte-identical stores only with identical encodings. These are normative.

A **closed** vocabulary is held by a schema `CHECK`: a value outside it is refused at the write, and adding one is a new schema version raising `read_version` (§6). An **open** one is checked by no constraint, so it grows within a version: a reader MUST read a value it does not know as this section says for that column, never as an error.

Closed: `kind`, `level`, `marks` and `base_marks`, `deleted` and `conflicted`, `conflict`, `support`, `origin`, `hash_algo`, and `item_reference.role`, whose `CHECK` also takes any name in an application's `x-` space. Open: `collections.role`, `action`, `capability`, `item_address.role`, `dtstart_value` and `due_value`.

**A kind added later locks older programs out.** `kind` being closed, a fifth kind is a value a migration adds, raising `read_version`: every reader and every producer of an earlier version then refuses the whole store (§4.2), one that lists nothing but mail included. This part accepts that cost rather than define what an unknown kind reads as in every store-wide read (the feed, the address axis, the references).

- **`kind`** (TEXT, on `collections`): `'message/rfc822'`, `'text/vcard'`, `'text/calendar'` or `'application/octet-stream'`, closed; `''` on a collection not yet declared.
- **`level`** (INTEGER): `1` meta, `2` full, closed.
- **`deleted`, `conflicted`** (INTEGER): `0` or `1`.
- **`conflict`** (TEXT, on a collection): `'manual'`, `'prefer-incoming'` or `'prefer-existing'`, closed; a `prefer-` policy keeps the body it does not adopt as a retained item (§11).
- **`flag`** (TEXT, on `placement_flag` and `binding_base_flag`): one raw flag, compared by its bytes, non-empty and printable ASCII without a space (`\Seen`, `$label`), as IMAP flags and JMAP keywords are. A set holds each flag once and has no order, and is read as §4.4 joins it. **`marks`**, **`base_marks`** (INTEGER, on `items` and `bindings`): the set's system flags, each by its exact bytes, as the sum of its bits: `\Seen` 1, `\Answered` 2, `\Flagged` 4, `\Draft` 8, `\Deleted` 16, `0` to `31` by constraint. Every other flag, `\seen` and `$Important` among them, is a row. **`flags_known`**, **`base_flags_known`** (INTEGER): `1` the bits and the rows are the set, none being known-empty; `0` unknown, holding no bit by constraint and no row by trigger.
- **`hash`** (TEXT, on `objects`): a name of §5, 52 characters of `a` to `z` and `2` to `7`, held by a `CHECK`. **`object_hash`, `base_object`, `conflict_object`** (TEXT): such a name, held by the foreign key onto `objects`, or `NULL`. **`hash_algo`** (TEXT, on `store_meta`): `'blake3'`, closed.
- **`refcount`** (INTEGER): the pointer count of §5, `>= 0` by constraint; `0` is a meaningful, collectable count.
- **`link_id`** (TEXT): never empty, by constraint; the hint verbatim, `esc:` and the hint when it begins with a reserved prefix (§9), a kind fallback, or a minted `dup:<key>#<handle>`, nested when minted again over a held key (§9); opaque.
- **`sort_key`** (TEXT): §9.3; `''` unknown; a timestamp as `2026-08-01T10:00:00Z`. The one column exempt from byte-identity: a zoned time resolves through a time zone database two writers may hold at different versions, and a wrong key loses nothing.
- **`changed`** (INTEGER, on `items` and `collections`): the stamp of §4.5, `-1` only inside the statement requesting one; `next_change` and `purges` (INTEGER, on `store_meta`) its counters, the second counting every item purged or evicted, every object collected and every collection renamed or deleted.
- **The summary columns**: Annex A's, decoded or verbatim as it says, an instant with the `Z` designator, `NULL` for absent and unknown unless it says otherwise. A message's `date` is held to the shape Annex A.0 writes an instant in (`2026-08-01T10:00:00Z`) by constraint, or `NULL`: §9 compares it byte for byte and a scope orders it as text, so no other text is taken, a fraction of a second and an offset included.
- **`role`, `address`, `position`** (on `item_address`): a role of Annex A.6, the canonical addr-spec, and the 0-based document order within the role. `role` is open: a reader reads a row whose role it does not know as naming its address in no role, so it lists the row under none of the roles it shows and still answers it where a read asks for any role (`list_address_placements`). A card's telephone has no row: the table holds addresses, and whether a card holds a `TEL` is the search index's to answer (`has:phone`, SEARCH.md §6).
- **`dtstart_value`, `due_value`** (TEXT, on the calendar summaries): `date-time` or `date` (Annex A.3, A.4), open: a reader meeting another value does not interpret the `dtstart` or the `due` beside it, reading the property from the body where it holds one, and otherwise shows no time for it, ordering the item by its `sort_key`.
- **`from_kind`, `to_kind`, `role`, `origin`** (on `item_reference`): a collection kind as `collections.kind` holds it; `attachment`, `invitation`, `sender`, `parent`, `source`, `related` or `x-` and a name; `auto` or `user` (§14.2).
- **`base_revision`** (TEXT): an opaque etag or modseq, or `NULL`.
- **`conflict_revision`, `conflict_object`** (on a binding): the remote revision and body observed when the binding was marked conflicted. A binding that is not conflicted MUST NOT carry either.
- **`shared_object`** (TEXT, on a binding): the shared body last reconciled against (§10), `NULL` until the source has folded once; counted (§5).
- **`created_at`, `retained_at`, `applied_at`, `refused_at`** (TEXT): `strftime('%Y-%m-%dT%H:%M:%fZ','now')`, stamped by SQLite (`init_store_meta`, `enqueue_action`, `retain_item`, `record_receipt`, `refuse_binding`, `add_reference`, and `covered_at`, `round_started_at` by `close_round`, `open_round`). Every instant the format fixes is UTC with the **`Z` designator**, never `+00:00`, which sorts apart from it. The shape of each is held by constraint, wherever a table holds one: four digits, two and two for the date, `T`, two, two and two for the time, a period, three digits and `Z` (`2026-08-01T10:00:00.000Z`), and no other text is taken.
- **`retained_by`** (TEXT): the source whose removal retired the item, diagnostic; `NULL` on a row that is not retained, by constraint.
- **`seq`** (INTEGER, on `items`): the public id of §9.1, at least 1 by constraint.
- **`id`, `account`** (TEXT, on `collections`), **`source`**, **`handle`** (TEXT, on `sources`, `bindings`, `capabilities` and `performers`): never empty, by constraint, `account` `NULL` or not empty; an empty text would read as `NULL` does in the keys folding the two (`capabilities_key`, `collections_by_role`, `performers_key`).
- **`size`** (INTEGER, on `objects`, `mail_summary` and `file_summary`), **`attempts`** (INTEGER, on `queue`): at least 0 by constraint. **`attachment`** (on `mail_summary`), **`recurring`** (on `event_summary` and `task_summary`): `0`, `1` or `NULL`, by constraint.
- **`checkpoint`**, **`round_cursor`**, **`round_checkpoint`** (BLOB): opaque cursor bytes, or `NULL`.
- **`covered_since`**, **`covered_until`**, **`round_since`**, **`round_until`** (TEXT): a scope's bounds, RFC 3339 UTC at seconds precision with the `Z` designator, as Annex A writes `date` (`2026-08-01T10:00:00Z`), that shape held by constraint; `NULL` an open bound. A message is in a scope when `since <= date < until`, or when its `date` is `NULL`.
- **`covered_at`**, **`round_started_at`** (TEXT): stamped by SQLite as `created_at` is (`close_round`, `open_round`); `NULL` no coverage, no round open.
- **`round`** (INTEGER): on a source, the last round id drawn, `0` before any; on a binding, the round that last listed its handle, `NULL` before one did.
- **`round_band`** (INTEGER, on a source): `1` while the open round lists only the band its coverage lacks, else `0`, and `0` with no round open by constraint.
- **`base_present`** (INTEGER, on a binding): whether a base exists. A base is present iff `base_present` is 1, the one witness every statement reads. A binding with no base holds no base flag set, no `base_object` and no `base_revision`, by constraint, so no other column states a base without it; a base naming nothing, a delivered create's, is `base_present` 1 with the three empty.
- **`refusal`**, **`refused_key`** (TEXT, on a binding): the refusal standing on it (SYNC.md §4, §5): the reason the remote gave for refusing a change of this source for good, free text scrubbed of credentials (§18), and the idempotency key of that change (SYNC.md §4), sixteen lowercase hexadecimal digits by constraint. With `refused_at` they are all three set or all three `NULL`, by constraint: `refuse_binding` sets them, `clear_refusal` clears them, and the binding's delete takes them.
- **`action`** (TEXT): `'add'`, `'set-flags'`, `'remove'`, `'move'`, `'copy'`, `'update'`, `'set-performer'` (§15.3), an intent of Annex B.2, or an application's own action, skipped by an owner that does not know it.
- **`capability`** (TEXT, on `capabilities` and `performers`): a name of Annex B, or an application's own starting with `x-`. **`collection`** (TEXT, on `capabilities`): `NULL` for the source-wide row, a collection id for an override there. **`account`** (TEXT, on `capabilities` and `performers`): the account of §9.2, `NULL` in a single-account store.
- **`support`** (TEXT): `'full'`, `'partial'` or `'none'`, closed. **`detail`** (TEXT): what a human reads about it, or `NULL`.
- **`payload`** (TEXT): versioned JSON with a leading integer `v`, the payload's version for its `action`, typed by the action's schema under payloads/ and parked when malformed (§15.3), a row whose `v` the owner does not know being skipped (§15.2), never read as a version it knows. **`target_collection`** (TEXT): the collection a `move` or a `copy` names as `to`, or the one an `add` names in `supersedes`, `NULL` for any other action; written by the producer with the payload, followed by a rename (§14), and read by the owner in place of the payload's own. **`object_hash`** (TEXT, on `queue`): the body the action carries, pinned (§15.1), read by the owner in place of the payload's `object` (§15.3), or `NULL`. **`error`** (TEXT): `NULL` while pending; set when parked. Its text is free, save one reserved prefix: a text beginning with `unconfirmed: `, the word, a colon and one space, says the row is an intent whose outcome is unknown (§15.2), and no other row's begins so: `unconfirm_action` alone writes it, and `park_action` records a failure text beginning with it behind `failed: `, whole.
- **`seq`** (INTEGER, on `receipts`): the public id (§9.1) of the item an applied action acted on: the item a `set-flags`, an `update` or a `remove` names, when the store holds it, the one an `add` created, the one a `move` or a `copy` left in its target; or of the item a performed intent left in the store when its performer knows it; `NULL` otherwise. **`collection`** (TEXT, on `receipts`): the collection the row was queued on, following its rename; `NULL` reads "its collection is gone", the row applied and the collection deleted since.
- **`generation`** (INTEGER): the epoch of §12, starting at 1.
- **`derivation`** (INTEGER, on `store_meta`): the Annex A revision of §6.
- **`sync_version`** (TEXT, on `store_meta`): `sync-draft-NN` or `sync-vN`, the version of the sync part whose engine wrote the sync state (§14), `NULL` before any did.
- **`format_version`** (TEXT, on `store_meta`): `storage-draft-NN` or `storage-vN` (§4.2). **`version`**, **`read_version`**, **`produce_version`** (INTEGER): schema versions, starting at 1.
- **`store_id`** (TEXT, on `store_meta`): 32 lowercase hexadecimal digits, 16 random bytes drawn by `init_store_meta`, never changed. **`incarnation`** (INTEGER): 1 at creation, raised by every restore (§8), never lowered; both held by `store_meta_identity`.

## 14. Operations

A store is opened as one source. `load` reads the shared items and that source's bindings, which a sync engine projects into placements (SYNC.md §3); `write` folds the source's changes back as a batch (below). Both are this part's interface, whoever calls them; the statements are §4.4's, bound with §13.

- **`load(collection, selection)`**: `load_items`, `load_bindings`, `load_conflict`, plus `load_checkpoint`, which answers the coverage beside the checkpoint, and `load_round`; a round's last page adds `list_unstamped_bindings`.

  The **selection** names what the caller needs and is a floor: `All` reads the collection; `Links` reads `load_items_by_link` and `load_bindings_by_link` for the link ids named, and answers who holds each key, never offering a create for an item the source lacks; `Handles` resolves each handle with `link_for_handle` and reads the same two, a handle nothing binds being a member to name. What owes a push is named by two statements, so a delta reads it without `All` (SYNC.md §10): `list_owing_bindings` the handles of this source's bindings whose placement may not be `Clean` (a binding or its item conflicted, the item deleted, no base, a known flag set differing from a known base, an object other than the base's), `list_lacking_items` the link ids of the live items holding a body this source binds not. Each names a superset, the projection deciding every status from the rows it loads. A store MAY return more than the selection names, never a retained item (§11.1), and MUST NOT return less.

  A `Created` placement's origin is `origin_for_link`, never a binding under a provisional handle, and a `Tombstone` placement's destination `destination_for_link`, a pending create or a delivered one (SYNC.md §3), each a seek on `items_by_link` for the key and for the key a minted form names, then on the binding's own key, so a projection reads them per placement, never every binding of the store. `list_superseded_pending` names the tombstones whose remove is held (§15.3, SYNC.md §5). `list_superseded_bindings` names, for each pending create superseding an item of its own identity, the member it may be moved from: the superseded item's binding of this source in its collection (SYNC.md §4). `list_refusals` names the refusals standing in the collection, whose changes a sync holds (SYNC.md §5).
- **`lookup_objects(account, links)`**: the link ids in the `links` slot (§4.4), `account` the caller's own (§9.2): across collections a link id is one body downloaded once where the rows agree (§9), across accounts it is not a fact. It answers, for each row of the account holding a body under one of the keys, the body's hash and size and the `subject`, `date` and `sender` the row's mail summary states, the three `NULL` for a row holding none: the witnesses a link is checked against (SYNC.md §6), one row per holder so the caller adopts from one that agrees. A writer-derived key never matches (§9).
- **`held_mail_summary(account, link_id, hash)`**: the mark and the invitation a row of `account` holding the body `hash` under `link_id` states, a row stating its mark first, for a placement linked to it (Annex A.1). A writer-derived key never matches (§9).
- **`write(ops)`** applies one batch (below) as one transaction, the statements each step names being the reference form (§4.4):
  1. A `StoreObject` carries the index row and optionally the bytes. With bytes, write the blob first (§5), then `store_object`; without, the body is already at its path, streamed there by the consumer through §5's write. The blob write MAY precede `BEGIN` and SHOULD for a body of any size; the writer's lock (§8), not the file's age, keeps a collector out of the window.

     A `SetCheckpoint` runs `ensure_collection` then `upsert_checkpoint`; a `SetCoverage` runs `set_coverage` beside it. A `DeliverPlacement` has the effect of `deliver_binding`. A `RefusePlacement` has the effect of `refuse_binding`, its reason scrubbed first (§18), and a `ClearRefusal` that of `clear_refusal`, each after the batch's upserts and drops, in the batch's order. A round's ops run `ensure_collection` then `open_round` (`OpenRound`), `stamp_bindings` after the upserts of the handles it names (`Stamp`), `set_round_cursor` (`SetRoundCursor`) and `close_round` (`CloseRound`), in the batch's order.

     Placement upserts and drops are merged into the shared items and bindings, `set_conflict` carrying the collection's policy. The reference form is the **diff**:

     - read `load_items_by_link`, `load_bindings_by_link`, the kind's `load_<kind>_summaries_by_link`, `load_addresses_by_link`, and for mail and tasks `load_in_reply_to_by_link` and `load_categories_by_link`, bound to the batch's link ids, each a seek per id however large the collection; a write merging a whole collection reads `load_items`, `load_bindings`, `load_<kind>_summaries`, `load_addresses_by_collection`, `load_in_reply_to` and `load_categories` instead;
     - resolve each dropped handle, and each upserted handle likewise, with `link_for_handle`, a handle bound to another link id retiring that binding first (§10);
     - then `insert_item`, `insert_binding`, `update_item`, `update_binding`, and `delete_binding` for a binding a `Deleted` drop removes, each row write carrying its set's system flags (`marks`, `base_marks`, `0` for an unknown set) and followed by its other flags' (§4.4): `retain_flags` and `add_flags` after the item's, `retain_base_flags` and `add_base_flags` after the binding's, the `flags` slot holding those flags (empty for an unknown set), both skipped where the set holds none and the row holds none;
     - and `delete_item_bindings` with `retain_item` for an item the result no longer holds, purged at once when `held_elsewhere` says the identity moved (§11, §11.1).

     `update_binding` carries no handle: a rebind is refused unless a drop of the bound handle in the same batch licenses it, with reason `Superseded` or `Rekeyed` (§10, §12).

     A named placement carries its summary and addresses, derived by the writer under Annex A and written with the item (`upsert_<kind>_summary`, `replace_addresses`, `insert_address`; for mail `replace_in_reply_to` and `insert_in_reply_to`, for a task `replace_categories` and `insert_category`). A calendar resource whose component changed under its key leaves its old table (`delete_event_summary`, `delete_task_summary`, `delete_journal_summary`).

     A placement is always named (below). An item left with no binding is retained (§11).
  2. Settle the refcount of every object the batch touched: `adjust_refcount` by the batch's net change, or `recompute_refcounts` for the whole store, which is also §7's repair. A batch that stored or dropped no object MAY skip this.
  3. Commit. The batch reclaims nothing (§5).

**The batch.** A writer hands the store its changes as a batch: one collection, one source, and a list of operations the store applies in order and atomically, and MUST NOT reorder. Order carries meaning: a batch names one handle twice to supersede a provisional one, and a rebuild drops every old handle before it upserts any new one. The operations are:

- `UpsertPlacement`: one placement of the source: its handle, its link id when the writer names the member, its flags, object, level, sort key, summary, address and list rows, base and conflict, merged into the shared item and the source's binding (§10, the diff above).
- `DropPlacement { handle, reason }`: the source's binding of a handle goes, for a reason:
  - `Deleted`: the member is gone from the source, or is a delivered create given up on request, which no listing ever named (SYNC.md §7); the item is marked deleted, and retained once no binding is left (§11);
  - `Superseded`: a provisional handle an accepted add or a landed arrival replaced, licensing the binding to move to another handle in the same batch (§10);
  - `Rekeyed`: a handle a rebuild renumbered, licensing the move too and making the batch a rebuild (§12).

  A `Superseded` or `Rekeyed` drop marks nothing deleted.
- `DeliverPlacement { collection, handle }`: the source's create under the provisional `handle` was delivered (SYNC.md §2, §4): its binding gains a base naming nothing, no flag set, revision nor body (`deliver_binding`), while it holds none. A binding holding a base, or no binding under that handle, is left as it is, the create having been landed, withdrawn or delivered since. A relocation's names its destination's collection, which the batch holds apart from its own (SYNC.md §5).
- `RefusePlacement { collection, handle, key, reason }`: the remote refused for good the change keyed `key` the source pushed for its binding under `handle`, giving `reason` (SYNC.md §4, §5): the binding records it, replacing a refusal standing there, and a handle nothing binds records nothing. An engine whose offered create is refused binds it first, by an upsert earlier in the batch (SYNC.md §5), so every refusal it writes has its binding.
- `ClearRefusal { collection, handle }`: the source's binding under `handle` had a push accepted (SYNC.md §5): the refusal standing on it is cleared.

  A refusal is the binding's under its handle: a drop of the handle takes it, a `Superseded` or a `Rekeyed` one included, and the binding an upsert then writes under another handle holds none. An upsert of the binding keeps it.
- `StoreObject { hash, size, bytes? }`: an object row, with its bytes, or naming a body a consumer already streamed to its path through §5's write.
- `Overrule { handle }`: the next upsert of `handle` in the batch settles its conflicts by an engine's or a connector's rule (SYNC.md §7), so each diverging body it does not adopt, the binding's `conflict_object` then the item's, is kept as a retained item (§11, SYNC.md §9). It MUST be refused when a conflict it settles holds no diverging body. With no conflict standing it keeps nothing.
- `Settle { handle }`: the next upsert of `handle` in the batch is a person's resolution of the item's conflict (SYNC.md §7): the item takes the upsert's body, or keeps its own when that upsert is a tombstone's, which adopts none, `items.conflicted` cleared and its `conflict_object` released, nothing kept. An item in no conflict ignores it.

  Both precede the upsert they qualify, and only they tell it from a sync's upsert, which leaves an item's conflict standing and keeps what a policy discards (SYNC.md §9).
- `SetCheckpoint { checkpoint }` and `SetCoverage { since, until }`: the source's checkpoint, and a narrower coverage it serves (§10).
- `OpenRound { since, until, band }`, `Stamp { handles }`, `SetRoundCursor { cursor, checkpoint }` and `CloseRound { since, until, checkpoint }`: a round's (§10). `OpenRound` comes first in its batch, `Stamp` after the upserts of the handles it names, and `CloseRound` last; a `SetRoundCursor` naming no cursor keeps the one recorded.

**What a batch may not do.** A placement is always named: an upsert for a handle nothing binds and carrying no link id MUST be refused, and an unlinked one for a handle a binding holds folds into that binding's item. An upsert resolving a binding to a different handle MUST be refused unless a `Superseded` or `Rekeyed` drop of the bound handle precedes it in the batch, and one resolving a bound handle to a different link id retires the old binding first (§10).

**The write keys another message apart.** An upsert naming a mail member by its bare hint is keyed by §9's table against every row the collection holds under that key, whatever the writer saw of them: a row holding a message the member does not agree with (§9), one another source binds included, gives the upsert the identity minted over its handle, minted again over a held key, and is never joined, landed nor revived. A writer that saw the row mints the same way first, so both name the member alike.

**Chunks.** A writer MAY cut one operation's writes into several batches, its **chunks**, each committed apart (an engine pushing in bounded chunks, SYNC.md §5). A body stored in one chunk may first be referenced by a later one, so the collector MUST NOT run between two chunks of one operation (§5), nor an eviction or a release below a date (§11.3, §11.4).

**The version of the sync state.** The rows an engine writes for its sources, **sync state** (`bindings` and their base flags, `sources`, and the cross-source columns `deleted`, `conflicted` and `conflict_object` of `items`), follow the sync part their engine implements. `store_meta.sync_version` names it: `NULL` until an engine writes, then its version (`sync-draft-15`, or `sync-vN` once released), written by `set_sync_version` in the transaction of the engine's first write and whenever another version takes the store over. What an engine does with a version it did not write is the sync part's (SYNC.md §10); a program writing no sync state never reads it.

The queue adds **`enqueue`**, **`drain`**, **`cancel`** and **`prune_receipts`** (§15); retention adds **`purge`** and **`purge_retained_before`** (§11.2), the owner's manual **`evict_before`** (§11.3) and **`release_before`** (§11.4), each reporting rows and never bytes. **`collect_garbage()`** is §5's collector, reporting the rows, files and bytes it freed.

A collection's `kind` is declared, never derived: `set_collection_kind(collection, account, kind)` sets it, `load_kind` reads it, and `ensure_collection` inserts an empty kind it MUST NOT overwrite. The account binds the same way: `set_collection_account` re-accounts a collection, `load_account` reads it.

A source offering a collection of another media type (a DAV collection of `text/x-vlist`) has it recorded with no kind, `''`, and never synced, the schema refusing the type.

A collection's `name` is a label, never an address: `set_collection_name(collection, account, name)` sets it, and `ensure_collection` seeds it with the id so a row always carries one. A reader renders `name` and addresses by `id`.

An owner namespacing its ids (§9.2) SHOULD record the bare name here, the separator being its own convention and not one a reader can strip. Nothing keys on the name, so a rename costs a label and never a re-sync; keeping it current across a `rename_collection` is the owner's.

A collection's `role` says what its source states it is for, `NULL` when the source states nothing:

- for `message/rfc822`, the JMAP `Mailbox/role` vocabulary (RFC 8621 §2: the IANA IMAP Mailbox Name Attributes, lowercased, plus `inbox`), `inbox`, `sent`, `drafts`, `trash`, `junk`, `archive`, `all`, `flagged` and `important` among them;
- for `text/calendar` and `text/vcard`, `default`: the collection the source writes to when none is named;
- for `application/octet-stream`, `attachments` (below).

The vocabulary is open (§13), so a role the registry gains later needs no new schema version. `set_collection_role(collection, role)` sets or clears it, an owner writing only on a declared collection and only a role of its kind's vocabulary. A reader MUST read a role it does not know, or one of another kind's vocabulary, as none.

An account holds each role of a kind at most once (`collections_by_role`): setting a role takes it from the collection that held it, in the same statement (`collections_role_moves`).

The owner writes a role only from what a source states (an IMAP special-use attribute, a well-known folder, a system label, a default flag), never from a name, and clears it when the source stops stating it. The exception is `attachments`, which no source states: the owner sets it on the file collection it keeps an account's stand-ins in (§14.3). With several sources on one collection, the first that states one wins, as for the name.

What a reader makes of a collection with no role (a name it recognises, a choice of the user's) is its own.

A source's **capabilities** are declared as a set, `delete_capabilities(source)` then `set_capability(account, source, collection, capability, support, detail)` per row, in one transaction (§15.6); a source the owner stops running has its set deleted the same way. A **performer** is recorded by `set_performer(account, capability, source)` and withdrawn by `delete_performer(account, capability)`, both applying a `set-performer` action (§15.3).

**`rename_collection(collection, new_id)`** is the only safe way to change an id. Every foreign key onto `collections(id)`, and `bindings`' key onto `items(id, collection)`, cascades, so items, bindings, sources, queue rows and children follow in one statement, an item's other children keyed by its id alone, and the items are restamped under the new id (§4.5).

A pending `move` or `copy` names its target, and a pending `add` the collection of the item it supersedes, in `queue.target_collection`, which no key cascades: `rename_queue_targets` MUST run beside it in the same transaction. The payload keeps the id it was enqueued with, and the owner reads the column. Deleting and recreating the row cascades the delete instead.

A bare `UPDATE` is refused under `NO ACTION`, and with `PRAGMA foreign_keys` off the rename cascades nothing. An account rename is one `rename_collection` per collection plus `set_collection_account`, in one transaction, the account's sources declared and its performers recorded again under the new id.

**`delete_collection(collection)`** removes a collection the operator no longer wants, everything under it cascading and retention not applying. A receipt of a row queued on it stays and names no collection (§15.4), and the delete counts in `store_meta.purges`, an empty collection's too (§4.5). It is the only sanctioned `DELETE` on `collections`.

It MUST NOT drop a queue row: a collection holding a pending or parked action is refused, which the schema holds (`collections_keep_queued`). The operator cancels each row (§15.5) or lets the drain apply it first, so an action, an intent included, never vanishes without a receipt or a report.

The cascade drops pointers no statement returns, so it MUST be followed by `recompute_refcounts` in the same transaction, which MAY be skipped when `collection_holds_objects` answered false before the delete; the bodies then fall to the collector.

### 14.1 Reading the store

A **reader** (§8) opens read-only and projects the store as a local backend. Reads are kind-agnostic where they can be, keyed by `seq`, and named after their statement.

- **`list_collections()`**, **`list_collections_by_account(account)`** (`NULL` selects a single-account store's), **`list_accounts()`** (accounts owning at least one collection, not a roster). **`list_coverage(collection)`** answers the coverage per source, with the round each has under way.

  A collection is listed with its coverage: the narrowest of its sources' (the latest `covered_since`, the earliest `covered_until`, the oldest `covered_at`), and none while one of them has never closed a round. A reader says "mail since" from it, and a search over the collection knows it is not exhaustive below it.
- **A `NULL` cursor is the first page** in every paged read below, whatever its order, each statement coalescing it to the bound before its first row (§9.3); the value that bound is (`''`, `0`) is read the same.
- **`list_items_page(collection, after, limit)`**: a keyset page in link-id order, the sweep that sees every item once.
- **`list_items_page_asc`**, **`list_items_page_desc`** `(collection, after_key, after_seq, limit)`: the natural order (§9.3), cursor `(sort_key, seq)`.
- **`count_mail(collections, seen, attachment, since)`**, **`count_mail_by_day(collections, seen, attachment, shift, since)`**, **`count_unread(collections, attachment, since)`**: the live mail of a set of collections under the read and attachment filters, `seen` and `attachment` (`NULL` for either), in all, per day of the `Date` on the reader's clock, `shift` its offset from UTC in whole minutes (`120` east, `-300` west, `NULL` UTC), and unread per collection, so a list is sized by a count before it loads. A count reads `mail_summary` only for the attachment filter, and tests the read filter on the item's `marks` bit, so a count reads no flag row; `count_unread` reads `items_unread`, the unread rows alone, so a mailbox mostly read is counted from what it has not read.
- **`list_mail_page_filtered`**: the page under the same filters across the set, cursor `(sort_key, seq, collection)`, merged from each collection's (§9.3). **`search_mail`**: the same page over a `LIKE` pattern on the subject, the sender and its name, never the body: the reader's filter for a store without an index, the search part (SEARCH.md) answering the body where one is built. A pattern one collection of the set never matches reads that collection's summaries whole. `LIKE` folds the case of ASCII letters alone and no accent, where the search part's index folds both (SEARCH.md §5), so the two answer differently on an accented letter. The store keeps `LIKE` and requires no FTS5 (§4.1): text search, indexed, is the search part's.
- `since` is a floor on the sort key (§9.3), an RFC 3339 instant: a row below it is left out, an undated one below any, and `NULL` sets none. It is a seek on the index, so a list cut at a date costs the rows above it, never the store's. `search_mail` takes no floor.

  A floor is a reader's window, not a sync scope: a scope holds an undated message (SYNC.md §5), so it is synced and kept, while a floor lists it only once it is `NULL`. A reader showing undated mail beside a window lists it apart.
- **`sum_mail(collections, seen, attachment, held, since, until)`**: what `count_mail` counts with a sort key in `[since, until)`, either bound `NULL` for open, as the messages, the summed `size` of those that know it and the count of those that do not, so a reader says what a range of dates weighs before downloading it.

  A message counts once however many collections of the set file it (its `seq`), its size the largest a placement states. `held` 1 keeps the messages a placement holds the body of, 0 those none does (what a download would fetch), `NULL` either. An undated row lies below every date, held only by a range open below.
- **`get_mail_row(collection, link_id)`**: one live mail row in `list_mail_page_filtered`'s columns.
- **`search_contacts`**, **`search_calendar`**, **`search_files`** `(collections, pattern, after_key, after_seq, after_collection, limit)`: `search_mail`'s `LIKE` over a contact's name and addresses, a calendar item's summary (and an event's location), a file's name, A to Z across the set, merged as `list_mail_page_filtered` is: the same filter for a store without an index, folding as `search_mail` does.
- **`describe_endpoint(kind, link_id)`**: a reference's end as a link shows it, its first live placement and a title from whichever summary it has (§14.2).
- **`list_mail_page_desc`**, **`list_contacts_page_asc`**, **`list_events_page_asc`**, **`list_tasks_page_asc`**, **`list_journals_page_asc`**, **`list_files_page_asc`**: the same page joined with the kind's summary. A mixed calendar merges its three pages on `(sort_key, seq)`, the page an item comes from saying which table holds it.
- **`get_mail`**, **`get_contact`**, **`get_event`**, **`get_task`**, **`get_journal`**, **`get_file`**: one item. **`list_attachments(account, link_id)`**: the files a message attaches (§14.3).
- **`get_item(collection, seq)`**, **`load_addresses(collection, link_id)`** (one item's people by role), **`count_items(collection)`**, **`seq_by_link(collection, link_id)`**.
- **`load_in_reply_to(collection)`**, **`load_categories(collection)`**: a mail's `In-Reply-To` ids and a task's categories, in document order, for a whole collection; **`load_in_reply_to_by_link`** and **`load_categories_by_link`** `(collection, links)` for a page's link ids, the `links` slot, a seek per id. A mail or a task row carries neither, as it carries no address (§4.4).
- **`list_link_placements(link_id)`**, **`list_object_placements(hash)`**: every live placement of one key, or one body, with collection and account. The first pairs by key, so a minted copy is paired with its twin by the body read alone.
- **`references_from(kind, link_id)`**, **`references_to(kind, link_id)`**: the references an item makes and receives (§14.2), whatever their endpoints' state.
- **`list_address_placements(address, role, after_key, after_seq, after_collection, after_role, limit)`**: every live placement naming one address, once per role it names it in, `role` `NULL` for any, newest first: the person axis, a keyset page on `(sort_key, seq, collection, role)`, `NULL` the first page, which reads the address's placements on `item_address_by_address` and holds the page alone. **`list_domain_placements(domain, role)`**: every live placement naming an address of one domain, newest first, by a scan, unpaged; the domain is compared as text, ASCII letters in either case, never matched as a pattern.
- **`list_replied(ids)`**: which of the message ids the `ids` slot names, bare as Annex A.1 and A.4 store them, a live mail's `mail_in_reply_to` names, mail under the `sent` or `drafts` role aside, each once: which of the mails tasks came from were answered. A seek per id on `mail_in_reply_to_by_id`.
- **`list_items_changed_since`**, **`list_collections_changed_since`**, **`load_change_cursor`**: the feed (§4.5).
- **`list_retained_page(collection, after, limit)`** (cursor on `seq`), **`count_retained`**, **`retained_bytes()`**: the trash view (§11), every deleted row, `retained_at` `NULL` on one a source still binds.
- **`load_capabilities(collection)`**, **`load_item_capabilities(collection, seq)`**: what every source syncing a collection, or binding one item, can do there, a row naming the collection winning over the source-wide one, an undeclared source listed once with no capability; an item's source also answers `held`, 0 when it binds the item as a pending create alone (§15.6).
- **`list_capability_sources(account, collection, capability)`**: the candidates to perform an intent anchored on a collection, or anywhere in the account when none is named. **`load_performer(account, capability)`**: the user's choice among them (§15.6).
- **`load_action(id)`**, **`load_receipt(id)`**, **`load_receipt_refusals(id)`**: one queue row by the id its enqueue answered, pending or parked, what it became once applied, and the refusals standing on the item it acted on (§15.4). **`list_refusals(collection)`**: every refusal standing in a collection, per item and source (§15.4).
- **`list_sources()`**, **`list_conflicted_bindings(account)`** (the bindings awaiting a decision with the three bodies the divergence is between, answered by index, never by paging), **`list_conflicted_items(account)`** (the items two sources disagree on, the same way), **`list_item_bindings(collection, link_id)`** (where one item lives per source), **`link_for_handle`** and **`handle_for_link`**, **`load_kind`**.

Three rules bind every read:

- **Live only.** A tombstone (`deleted = 1`) is never presented as live; the trash reads are the exception and present their rows as deleted.
- **Level-aware.** `level` says the tier reached, `object_hash` whether a body is there. A reader renders a list from the summary and treats an absent body, or a blob file gone under a purge, as not yet hydrated, never as an error.
- **Snapshot-consistent.** A reader sees a WAL snapshot and may run beside the owner. It detects change by `PRAGMA data_version` or the feed, and MAY overlay pending actions (§15.4).

### 14.2 References

A **reference** says that one item bears on another: a message and the file it attaches, an invitation and its event, a mail and the contact who sent it, two things a person linked. It is a fact recorded once, never derived from content nor recomputed. Nothing requires one: an owner MAY record references and a reader MAY ignore them.

- **Endpoints** are a collection kind and a `link_id`, never a collection: one identity filed in several collections is one endpoint, and a move keeps its references. The kind is part of it, a vCard and an event sharing a UID being two endpoints. No foreign key holds them.
- A writer-derived key (`alt:`, `hash:`, `dup:`, §9) names no identity (two unrelated messages may share one `alt:` key), so it is no endpoint, nor is a `part:` key over one. `add_reference` and the rules record nothing for it, and the schema refuses it. A message without a `Message-ID`, or a card without a `UID`, takes no reference.
- **`role`** is closed with an extension space (§13): `attachment`, `invitation`, `sender`, `parent`, `source`, `related`, or an application's own, `x-` and at least one more character, the schema refusing anything else. **`origin`** is `auto`, recorded by a writer's rule, or `user`, by a person, so a reader can say why a reference exists and undo a rule's references without touching a person's.
- **`add_reference`** records one between two endpoints the store holds, each with at least one row of `items` in a collection of its kind, and records nothing otherwise. An item never refers to itself.
- A reference is unique on its endpoints and role: recording it again changes nothing, save that `user` takes over `auto`, never the reverse. `add_reference` answers the reference as it stands, recorded now or before, and no row when an end is missing or derived, so a caller tells "linked" from "cannot link".
- **`remove_reference`** deletes one, whatever its origin. A rule matching again records it anew; no suppression is kept.
- **A reference goes with the last row of either endpoint.** `items_drop_references` deletes it when a delete leaves no row of `items` (live, tombstoned or retained) under that link id in a collection of that kind: a purge, an eviction (§11.3) or a collection's delete of the last copy.
- A move, a tombstone, a retention and the loss of one copy among several keep it, so a restore finds it. Every reference's two endpoints are therefore held. Whether an endpoint is live is the reader's to ask (`list_link_placements`).
- A reference stamps nothing in the feed (§4.5) and is local to the store: no source learns of it, and another store records its own.

**Automatic references.** An owner MAY record references by rule; one that applies a rule below MUST record what its statement records, so two owners over one store record the same references.

A rule's reference runs from the item whose content states it to the item it names, origin `auto`, both ends live when recorded, and never alters one already recorded, a person's included. Each rule has a statement per end, run after the write that changed what it reads, in that transaction or the next. A `NULL` link id runs it over every item of that end, which backfills a store.

- **`sender`**: a mail to every contact holding one of its `from` addresses as an `email` (Annex A.6). `link_senders_of(link_id)` after a mail's addresses are written, or `link_senders_of_by_link` once over the mail the `links` slot names, a page's; `link_mail_from(link_id)` after a contact's, so a contact added, or given an address, has its history. An address removed removes nothing; two contacts holding one address both receive it.
- **`invitation`**: a mail to the calendar item its `invitation` names by link id (Annex A.1). `link_invitations_of(link_id)` after a mail's body is read; `link_invitations_to(link_id)` after a calendar item's write, so an event synced after its invitation is tied to it.
- **`attachment`**: a mail to the stand-ins of its parts, recorded with them (§14.3).
- **`parent`**: a task to the calendar item its `parent` names by link id (Annex A.4), never itself. `link_parents_of(link_id)` after a task's summary is written; `link_parents_to(link_id)` after a calendar item's write, so a project synced after its actions is tied to them.
- **`source`**: a task to the mail its `mid` names by link id (Annex A.4). `link_sources_of(link_id)` after a task's summary is written; `link_sources_to(link_id)` after a mail's, so a mail synced after the task made of it is tied to it.

### 14.3 Files

A **file** is an item of a collection of kind `application/octet-stream`: an identity, its `link_id`, pointing at its current body, its `object_hash`, which an edit moves to a new blob. A **folder** is such a collection, holding nothing a filesystem would mirror.

A file's name is its summary in that folder (Annex A.7), so a rename is a summary write and a move one placement, and one file in two folders is two rows sharing a `link_id`, a `seq` and a body. The file's own media type is its summary's, never the collection's kind, which says only that the body is bytes.

- **A file is mutable**: a source syncing a folder reports revisions, and an edit, a push gated on the base and a divergence follow the content axis as a card does (SYNC.md §5). Nothing kind-specific is added to the base or the conflict.
- **A collection no source syncs** holds items no binding names: a folder on the device, the attachments collection below, or a calendar collection holding what a person keeps on the device alone. The owner writes them directly (`insert_item`, then the kind's summary: `upsert_file_summary`, `upsert_event_summary`, `upsert_journal_summary`); §11's retention, which follows a binding vanishing, does not apply to them, and no projection offers them.
- **An attachment** is a file inside a message's body, stood for by a file holding no body: `object_hash` `NULL`, `level` `1`, its summary naming the part (`part`, the IMAP section of RFC 3501 §6.4.5), keyed `part:` (Annex A.7).

  A part is stood for exactly when it makes the attachment mark (Annex A.1): it is disposed as an attachment, or sent bare as a file. A message under a writer-derived key gets none, its key naming no identity (§9).

  **At most 1,000 per message**: the first 1,000 parts making the mark, in the order the walk reads them (Annex A.1), are stood for and no later one, so one message's stand-ins are written in one bounded transaction. A message holding 1,000 stand-ins may hold more such parts, so a reader listing its attachments (`list_attachments`) that finds 1,000 reads the rest from the message's body, held or fetched from its source.

  It lives in a collection of the file kind, one per account, that no source syncs, since the message's own collection holds another kind: the account's file collection holding the role `attachments`, which tells it from a folder. When the account has none, the owner declares one with that role, named `attachments`.

  That collection's id SHOULD be the account, `/`, `U+0001` and `attachments` (`work/\u0001attachments`), or `U+0001` and `attachments` alone for collections under no account (§9.2), a name no server gives a mailbox, so two owners of one store declare the same.

  An `attachment` reference from the message (§14.2) ties them, and the owner MUST record the file and that reference in one transaction.

  A `Meta` row with its summary claims nothing (SYNC.md §6), so no sync or upgrade reads the missing body as one to fetch: a reader opens the part from the message's body when held, or has the message's source fetch the part alone. `list_attachments` reads a message's files, `list_attachments_by_account` every stand-in of an account with the message attaching it.
- **Stand-ins are recorded as the body enters.** An owner recording attachments records a message's stand-ins in the transaction that stores its body, whatever stores it: a fetch, an upgrade, an applied `add`, a write of its own.

  A body enters when no row of its key in the account held it before that write (`lookup_objects`). So a move, a copy, a second label or the same body stored again records nothing, and a body released (§11.4) then fetched again finds its stand-ins in place, a part the collection holds keeping its own.

  A body the store held before its owner recorded attachments is never walked for them: a stand-in is recorded once, at the instant its body enters, never backfilled and never recomputed.

  **A key stands for one message.** A `part:` key is built over a `Message-ID`, which two messages of an account may share while §9 keeps them apart, each in its own collection under its own `seq`. A body entering under a key another row of the account holds another body under, a message it does not agree with on `subject`, `date` and `sender` (§9, the three `lookup_objects` answers beside each holder's body), records no stand-in and no `attachment` reference: the keys are that message's, whose rows are neither replaced nor joined by another message's parts. A reader showing such a message lists the stand-ins its `Message-ID` names, the other message's, and opens each part from the body of the message it shows, as it does past the 1,000th.
- **Saving an attachment** places the same `link_id` in a folder with its own body: the stand-in stays, the saved copy holding a blob several messages may share.
- **A stand-in goes once no reference names it**: `item_reference_collects_files` deletes a file of a collection of that kind holding no body and bound by no source when a reference is deleted and none names it any more, so a message gone with its last row (§14.2) takes its stand-ins. A file holding a body, or one a source syncs, is never collected this way.
- **A local calendar collection** holds calendar items a person keeps on the device rather than in a synced calendar: a collection of kind `text/calendar`, that no source syncs, holding events and journals as any calendar collection does, declared with `set_collection_kind` and written as the bullet above says.

  An id beginning with `U+0001` is one no server gives, so a convention naming one lets two owners of one store find the same. Moving an item to a synced collection later is a copy of its body there and a delete here.
- **Deleting an unbound item**: `delete_unbound_item(collection, link_id)` removes an item no source binds, a file of a folder on the device, a stand-in or an item of a local calendar collection, and answers the hashes for `release_pins` in the same transaction; a bound item is its source's to remove.

## 15. Action queue

Only the owner mutates (§8), yet other processes originate mutations. The `queue` table is their write door: a **producer** appends an action, the **owner** applies it.

Actions address collections and public ids, so the same mutations serve every domain; intents (Annex B.2) carry what is not a store mutation, and an action's name is an open string beside a versioned payload. What a source supports is declared beside the queue (§15.6), so a producer can ask before it appends and the owner parks what no source supports.

### 15.1 Producing

A producer enqueues in one transaction: `ensure_collection`, at most one `store_object` and its `pin_object` when the payload names a body (the blob written first, §5), then `enqueue_action` carrying the hash in `object_hash`, the payload's `object` restating it, the pin being the count of that pointer (§5).

`created_at` is stamped by the statement, and the row's `id` is the handle the producer follows it by (§15.4). This is the only write a non-owner may perform, and when the owner applies it is the owner's (§8).

A producer MAY enqueue several actions in one transaction, each on the terms above, its body stored and pinned before its `enqueue_action`: all of them are appended or none, in the order enqueued, which their ids keep. It holds the staging lock across them all (§8).

### 15.2 Applying

The owner drains the pending actions store-wide in ascending `id` (`list_pending_actions`), the append order a producer relies on.

An action is applied and its row deleted in one transaction, which spans no network I/O. That transaction records the row's receipt (`record_receipt`): its `id`, its collection and the `seq` of the item it acted on: the item a `set-flags`, an `update` or a `remove` names, when the store holds it, the item an `add` created, read back by `seq_by_link` on the key it staged, and the one a `move` or a `copy` left in its target, read back the same way there.

The handle draining is not the source an action is for. An action against an existing item runs as a source binding it, an `update` or a `remove` stating `resolves` (§15.3) as one whose conflict it names when a binding of the item is conflicted; an `add` runs as a source syncing the collection, a binding or a checkpoint (`collection_sources`), the owner's own source where it is among them. A store-wide drain thus never binds a source to a collection it does not sync.

`claim_action` runs **first** in the transaction. The pending list is read outside any transaction, so a row it names may be gone by the time its turn comes, cancelled (§15.5) or applied by another handle of the owning process. A claim that deletes nothing means the row is not this transaction's to apply.

**A run of actions in one transaction.** An owner MAY apply a bounded run of pending actions in one transaction, in ascending `id`, each under a savepoint of its own: the savepoint opens, `claim_action` runs first in it, the action is applied, its receipt recorded, and the savepoint released. The bound is the owner's, and the transaction still spans no network I/O. Every action of a run is applied exactly once or not at all: the commit lands every released savepoint together, and a transaction that does not commit applies none, each claimed row restored.

A failed apply MUST be rolled back before anything else, which restores the claimed row and undoes whatever the apply wrote: its transaction, or in a run its savepoint alone, the actions applied before it standing. The park or the retry is recorded only after that rollback, in a transaction of its own or, in a run, in the run's transaction outside the savepoint rolled back, and the run goes on with the next row.

A failed action is retried (`bump_attempts`), a bounded number of times the owner chooses, then parked. One the owner judges permanently unappliable is parked at once (`park_action`): the attempt counted, `error` set, the action skipped, later ones proceeding, read back with `load_parked_actions` and never silently deleted.

A failure of the store itself (a refused rebind, a constraint, a target collection with no declared kind) is permanent for the row and MUST park it. Only a failure of the environment (the database busy, a body unreadable) is retried, and neither MUST stop the rows behind it.

An `add` or an `update` whose body cannot be read (its blob missing, failing to read or failing its name, §7) MUST be retried, then parked once the owner's bound on attempts is reached. It MUST NOT be applied without its body.

An `update` or a `remove` meeting a conflict, the item's or that of the binding it runs through, MUST be parked naming the conflict unless it is a resolution naming it, and one stating `resolves` and meeting none MUST be parked too (§15.3): applying either would settle a conflict nobody decided, or one decided over another body. A `move` meeting one MUST be parked naming it, whatever it states: it carries no resolution, and its tombstone would leave the conflict standing under a placement no listing shows. A `move` into the collection its item is in MUST be parked too, naming that collection (§15.3).

A `set-flags` stating `base` and meeting an item whose flag set is unknown MUST be parked (§15.3): there is no set to change.

**An intent whose outcome is unknown.** A performer that sent an intent's request and cannot tell whether it took effect (a submission whose connection dropped once the message was handed over) MUST park the row with an `error` beginning with the reserved prefix `unconfirmed: `, the text after it free (§13), which is `unconfirm_action(id, detail)`: the attempt counted, the prefix written by the statement before `detail`, the id of the row answered. It MUST NOT perform it again of its own accord: the effect may be made, and a second one is not undone. Annex B.2 says which intents can end so. An action the owner applies itself never does, its apply being a transaction of the store, which commits or does not: `unconfirm_action` writes nothing over one and answers nothing.

`unconfirmed: ` is the one reserved prefix of `queue.error`: no row in another state carries it, and any other text is free. The statements hold it. `park_action` records a failure whose text begins with the prefix, a server's error relayed as it came say, behind `failed: `, the text kept whole after it, so that row reads parked and never as an unknown outcome; an owner parking through a statement of its own (§4.4) writes the same.

A parked row is listed by no drain, so nothing retries it. It leaves that state in three ways only (§15.5): confirmed by its performer, which acknowledges it with its receipt once it learns the effect was made; retried on a person's request, who accepts that it may be performed twice, `retry_action` putting it back among the pending rows; or withdrawn, by `cancel_action`. A producer following the row tells the state by the prefix (§15.4).

**Skipping is not parking.** An owner that does not recognise an action, does not know the payload version `v` a row states for an action it knows, or does not run the source an intent names, MUST leave the row pending and untouched (`error` `NULL`, `attempts` unbumped) and MUST NOT block later actions on it. A payload it does not know is read no further: whether its other members would be valid at a version the owner knows decides nothing, and it is never parked as malformed.

A capability a declared source does not support is not a skip: the row is parked (§15.6). A drain has three outcomes per row: applied, parked, skipped.

### 15.3 Actions

Existing items are addressed by `seq`. A payload is a JSON object, typed by the JSON Schema (2020-12) of its action and version, payloads/<action>.v<v>.schema.json, which binds. The shapes below and in Annex B.2 restate them: `n` an integer from 1, `hash` an object name (§5), `key`, `id`, `collection`, `addr` and `label` a non-empty string, `text` any string, `[…]` a flag set as distinct flags (§13), `[addr…]` a non-empty array of `addr`, `[hash…]` a non-empty array of distinct `hash`, a quoted value the member's one value and quoted values joined by `|` its choices, `?` an optional member, and `( a | b )` exactly one of two members.

**A payload is valid whole, malformed or unknown.** A payload whose action and `v` an implementation knows is typed by their schema: one missing a member its schema requires, stating one of another type, or holding a member its version does not define is malformed: a producer MUST NOT enqueue it, and an owner knowing its action and version MUST park it, an intent's performer likewise, never applying it in part nor ignoring a member. One whose action it does not know, an application's own (`x-`) included, or whose `v` it does not know for an action it knows, is **unknown** to it, neither valid nor malformed: an owner skips it (§15.2) and a reader lists it (§15.4). A payload of an action it knows that states no `v`, or a `v` that is not an integer, is malformed and parked, never skipped: it states no version an owner could come to know, and a row waiting on it would wait for ever. A `v` is an integer as JSON writes one (RFC 8259 §6), digits with neither a fraction nor an exponent: `1.0` and `1e0` are no integer here, though a JSON Schema validator reads either as the integer 1, so this one rule is the text's and not the schema's, and a payload stating such a `v` is malformed. A payload changing shape, a member added included, takes the next `v`, which an owner not knowing it skips. While this part is a draft, a payload's shape at its `v` is edited in place, as version 1 of the schema is (§4.2), a draft's store opening under that draft alone. vectors/payloads.json holds valid and malformed payloads of every action, and unknown ones. At `v: 1`:

- **`add`**: `{ "v": 1, "link_id": key?, "flags": […], "object": hash, "supersedes": { "collection": collection, "seq": n }? }`. Creates an item staged as a local creation to push under its provisional handle (§2); the owner derives its summary and addresses from `object` (Annex A).

  A live duplicate `link_id` (`live_item_for_link`) parks the action: a source's duplicate is minted, a producer's is a mistake worth reporting. A retained row under the key revives (§11), and a tombstone still propagating is revived the same way, the new content beating the delete on every source; a message that does not agree with either is another one, and is minted instead (§9's table, its `Add` column).

  With `"supersedes": { "collection": id, "seq": n }` the add replaces the item it names (a task filed into another collection, renamed or not) rather than moving it there. In one transaction the owner applies the add, tombstones the superseded item as a `remove` of it would, and records the pair (`supersede_item`).

  The duplicate check reads the store before the tombstone, so an add parked for a live duplicate removes nothing. A superseded item already absent is no failure, the add applying alone; one no source binds is retained at once, nothing having a delete to push. A malformed `supersedes` parks the action.

  The tombstone's remove is **held** while the item the add created is live and a pending create of a source syncing its collection (`list_superseded_pending`): no source pushes the delete (SYNC.md §5), so a create its server refuses leaves the superseded item where it stood on every server. Once each such create is accepted, or the created item is withdrawn or gone, the delete is pushed as any other.

  A superseding item keeping the superseded item's identity (a task filed elsewhere with its `UID` kept) names the binding it may be moved from (`list_superseded_bindings`). A connector moving members server-side delivers the create by moving that member, so a server keeping one `UID` per account never holds the identity twice, and the delete pushed after it finds the member gone.
- **`set-flags`**: `{ "v": 1, "seq": n, "flags": […], "base": […]? }`. Sets the item's flags.

  Without `base` it replaces the set, absolutely, by `flags`. A producer writing a set it never read (a set stated whole by the user, over an item whose flags are unknown) states none.

  `base` is the set the producer read and changed into `flags`. The owner then applies the change alone, to the set the item holds when the row is applied: the result is that set, plus each flag `flags` holds and `base` lacks, less each flag `base` holds and `flags` lacks, every other flag left as it stands. A flag a sync landed on the item, or removed from it, after the producer read so survives the row, and the push derived from it (SYNC.md §4) names only what the producer changed. A producer changing a set it read SHOULD state it.

  A row stating `base` and meeting an item whose flag set is unknown MUST be parked: there is no set to add to nor remove from, and replacing would write the unread flags as removed.
- **`remove`**: `{ "v": 1, "seq": n, "if_match": hash?, "resolves": [hash…]? }`. Tombstones the shared item, every source that binds it pushing the delete (SYNC.md §9); already absent is success, and bound by nobody it is retained at once (below).

  `if_match` and `resolves` read as an `update`'s do (below), on the same rules. `if_match` is the body the producer read and deletes: when the item's current body is another, or the item holds none, the owner MUST park the row, naming both, the delete having been decided over a body the item no longer holds. A producer deleting a mutable item it read SHOULD state it; a row without it removes whatever the item holds.

  `resolves` makes the remove a person's resolution of a conflict by deleting, naming the `conflict_object` of each conflict the producer showed. A remove meeting a conflict, the item's or that of the binding it runs through, MUST be parked, naming the conflict, unless `resolves` names the `conflict_object` of each conflict it meets; one stating `resolves` and meeting none MUST be parked. So a remove queued before a conflict arose, or without it in view, never deletes a diverging body nobody saw, and one whose diverging body nobody has read is named by no resolution. A producer MUST NOT state `resolves` on any other remove.
- **`move`**, **`copy`**: `{ "v": 1, "seq": n, "to": collection }`, a `copy` being a `move` without the removal. The producer writes `to` as `target_collection` too, as it writes an `add`'s `supersedes.collection`, and the owner reads the target from the column, which a rename follows (§14). A target the store does not declare, or of another kind, parks the action rather than ensuring a collection nothing configured. A `move` whose target is the collection the item is in MUST be parked, naming it, and a producer MUST NOT enqueue one: applied, it would tombstone the item and stage a create beside it under a minted key (SYNC.md §7), which for an item held without its body never delivers while the tombstone pushes a delete. A `copy` there is a second copy, minted as any create beside a live holder is.

  A `move` meeting a conflict, the item's or that of the binding it runs through, MUST be parked, naming the conflict: a `move` states no `resolves`, so it is never a person's resolution, and the diverging body would stay pinned under the tombstone it leaves, where nobody is shown it. The conflict is settled first, by an `update` or a `remove` stating `resolves`, and the item moved after. A `copy` meets none: it tombstones nothing, and the conflict stands on the placement it copies from.
- **`update`**: `{ "v": 1, "seq": n, "object": hash, "if_match": hash?, "resolves": [hash…]? }`. Repoints a mutable item's body; the owner re-derives its summary and addresses.

  `if_match` is the body the producer read and replaced. When the item's current body is another, or the item holds none (a pull having emptied it, SYNC.md §5), the owner MUST park the row, naming both, an absent body as none: the body the producer read is not what the item holds, and applying the row would drop another write without a merge (SYNC.md §7). A producer editing a body it read SHOULD state it; a row without it applies over whatever the item holds.

  `resolves` makes the update a person's resolution of a conflict, naming the diverging bodies it was decided over: the `conflict_object` of each conflict the producer showed, the item's (`list_conflicted_items`) and its bindings' (`list_conflicted_bindings`). A producer deciding a conflict (a resolution command or form) states it, and MUST NOT state it on any other update: an ordinary edit, written before a conflict arose or without it in view, never settles one.

  An update meets a conflict when the item is conflicted (`items.conflicted`) or the binding it runs through is (`bindings.conflicted`, §15.2). One meeting a conflict MUST be parked, naming the conflict, unless `resolves` names the `conflict_object` of each conflict it meets; one stating `resolves` and meeting none MUST be parked, the conflict it was decided over being settled already. A conflict whose diverging body nobody has read, its `conflict_object` `NULL`, is named by no resolution. A resolution applied settles what it meets as SYNC.md §7 settles a person's `Edit`, and what it discards it loses.
- **`set-performer`**: `{ "v": 1, "capability": capability, "source": id? }`, `capability` a name of Annex B or an application's own (§13). Records `source` as the performer of an intent capability for the account of the collection the action is anchored on (`set_performer`), or withdraws the choice when `source` is absent (`delete_performer`). A `source` that does not declare the capability parks the action.

**The body is the column's.** An action carrying a body (an `add`, an `update`, an intent such as `submit`) names it in `queue.object_hash`, which the schema holds to the name of a stored object (§5), and an `add` or an `update` restates it as the payload's `object`. The owner reads the body from the column and never builds a path from the payload: a row whose payload's `object` is not the column's value, the column `NULL` included, MUST be parked, naming both.

**An item no source binds** is the store's alone to settle: an owner MUST apply or park an action naming it, never skip it, since nothing would ever bind it for the row's sake.

- A `remove` retains it (`retain_item`, §11), nothing having a delete to push, on the terms above, `if_match` and `resolves` included.
- In a collection no source syncs (`collection_sources` answering none, as for a local collection, §14.3), a `set-flags` and an `update` apply to the item directly: a `set-flags` on the terms above, its `base` included, an `update` on the terms above, `if_match` and `resolves` included, its summary and addresses derived again, and a body deriving none, or deriving another key, parking the row.
- There a `move` or a `copy` parks, there being no binding to carry; a producer filing such an item elsewhere writes it there with an `add` superseding it (above).
- In a collection a source syncs, any other action parks naming the item: it awaits its first push as every syncing source's `Created` placement (SYNC.md §3), and an action on an existing item runs as a source binding it (§15.2), which none does. The producer queues it again once a push has bound the item.

The intents of Annex B.2 are actions of their own, versioned the same way. An application MAY carry further ones; the store owes them append order, blob pinning and the skip rule.

### 15.4 Reading the queue

A reader MAY overlay a collection's pending actions (`load_pending_actions`) for read-your-writes. An overlay SHOULD fold a row as the owner would apply it to the rows the reader sees: a `set-flags` stating `base` as the change it is, over the set the item shows; and nothing for a row the owner would park (§15.2, §15.3, §15.6), among them a `set-flags` stating `base` over an unknown set, an `update` or a `remove` whose `if_match` names another body than the item shows, the item showing none included, or one meeting a conflict its `resolves` does not name, or a `move` meeting a conflict or into the collection its item is in, and an action on an item no source binds that the rules above park. An overlay is a prediction the drain may contradict (a body it cannot read, a capability declared since): a producer gating a write on what it shows states `base` or `if_match`, which the owner checks again (§15.3), never trusting the overlay alone.

A row whose action, or whose `v`, the reader does not know (§15.3) is folded into nothing and still listed as pending, with its action and its `created_at`: it is somebody's write the reader cannot show, never one it may hide.

A producer follows one row by the `id` its enqueue answered, under the store id and incarnation it recorded with it (§4.5). `load_action` reads the row while it is pending (`error` `NULL`) or parked, a parked intent whose `error` begins with `unconfirmed: ` being one whose outcome is unknown (§15.2): neither performed nor failed, which a producer shows as such. Once it is gone, `load_receipt` says it was applied and which item it acted on, the one it created for an `add`, a `move` or a `copy`, so a producer learns the `seq` of what it staged without matching the body. A receipt outlives the collection its row was queued on: once that collection is deleted, by the `collection-delete` the receipt answers or otherwise, its `collection` reads `NULL`, the row applied all the same.

A performed intent leaves a receipt too, acknowledged or replaced (§15.5), so a producer tells a message sent or a collection created from a row withdrawn.

**A refused push.** A row applied is pushed by every source syncing its collection, and a source's remote may refuse that change for good (SYNC.md §4): an append its server takes into one folder alone, a time its calendar does not take. The refusal stands on the binding of the item it was pushed for (SYNC.md §5), and `load_receipt_refusals` reads, beside the receipt, the refusals standing on the item the row acted on: per collection filing it and source binding it, the reason and when it was recorded. The item is every row of the receipt's `seq` in the account of the collection the row was queued on, so a `move` reads the create it left in its target. A producer shows such a row applied and refused by that source, with the reason: a state beside pending, parked and gone.

The row is not parked again, its effect being in the store: retrying it would apply it twice, and cancelling it would leave the item. The way out is an action on the item: a `remove` withdraws a refused create, whatever the source's delete right (§15.6, SYNC.md §7), and an `update`, a `set-flags` or a `move` stages a new change, which the source is asked again (SYNC.md §5). The refusal is cleared by that source's next accepted push of the item, and goes with its binding. `list_refusals` reads every refusal standing in a collection, for a view beside its queue.

A row found in neither was cancelled by request (§15.5), or applied longer ago than its receipt is kept: the owner keeps a receipt at least seven days after `applied_at`, and while a refusal stands on its item, then MAY drop it (`prune_receipts`). A row withdrawn by request leaves no receipt; the store change replacing an intent (§15.5) is a row of its own, followed by its own `id`.

### 15.5 Cancelling and acknowledging

`cancel_action` removes a pending or parked row, returning its pin: an operator withdrawing it by request, or the performer of a capability-bound intent acknowledging it. It is an owner write and MUST run in one transaction with `release_pins` on what it returned. An applied action cannot be cancelled: application deleted its row.

A performer acknowledging an intent it performed MUST record the intent's receipt (`record_receipt`) in that same transaction: its `id`, the collection it was queued on and, as `seq`, the item its effect left in the store when the performer knows it, `NULL` otherwise (a collection created, which arrives with a later sync; a message sent, its copy filed by the provider).

A withdrawal records none, which is how a producer tells the two apart (§15.4). An intent that failed is parked or left pending, never acknowledged.

**Retrying.** `retry_action(id)` puts a parked row back among the pending ones, on a person's request and never of the owner's own accord: its `error` is cleared, its `id` and its `attempts` kept, so the next drain lists it in its place in the append order and it is applied or performed as any pending row is. It answers the id of the row it put back, and nothing for a row that is pending or gone. It is the one way an intent parked `unconfirmed: ` is performed again (§15.2).

An intent whose effect is not a store mutation is therefore at-least-once, and deduplicating is the performer's.

An intent that leaves a store change behind, the copy of a sent message, is acknowledged by replacing it: in one transaction the performer enqueues that change as an ordinary action, through `enqueue_action` with its body pinned, then cancels the intent, records its receipt with a `NULL` `seq` and releases its pin. The change exists only once the intent is performed, and the drain applies it like any other, gated as §15.6 says.

### 15.6 Capabilities

Sources do not push the same things. The owner declares what each can do in the store and parks an action no source concerned can carry out (the owner's backstop, below), so a gap shows as a parked row rather than as a rejected push; a producer reading the same rows before it enqueues (the producer's gate) shows it at the action.

**Declaring.** The owner declares every source it runs, under the account the source syncs for: `delete_capabilities`, then one `set_capability` per capability, in one transaction, before it drains an action for that source and whenever the source's configuration changes.

A row names a capability of Annex B, or an application's own starting with `x-`, with `support` `full`, `partial` (the `detail` says what is missing) or `none` (the `detail` says why). A declaration MUST write every capability of Annex B's base set the owner knows of the kinds the source syncs, `none` included, so a source supporting nothing still says so. A source declares what it pushes as configured: a right its configuration withholds (SYNC.md §5) is `none`.

A row with no `collection` holds for the whole source. A row naming a collection overrides it there alone, for what the source does otherwise in one collection: a calendar shared read-only, a label the provider reserves. The owner writes one only where the collection differs, read from the remote's access rights.

A source with at least one row is **declared**, and a capability of Annex B's base set it has no row for, or a `none` row, is unsupported. A source with no row is **undeclared**, and nothing below gates it.

**Capabilities added later.** A capability Annex B adds after its base set is read only where a row states it. A declared source with no row for it was declared by an owner that did not know it, so it is neither supported nor refused there: nothing below gates an action by it, the producer's gate and the owner's backstop alike, and an intent it names has no candidate there (below).

An owner that knows it writes it, `none` included, as it writes every other. A row stating it, `none` or not, binds as any other row does.

**The sources concerned.** The capabilities an action needs (Annex B's table) are read against:

- for an action on one item, every source binding it (`load_item_capabilities`), but, for a `remove`, a `move` or a `copy`, one binding it as a pending create alone (`held` 0), whose server holds nothing of it yet: the remove withdraws that create and pushes nothing (SYNC.md §7), and a move or a copy reaches that source in the target alone (below), so neither needs its delete right nor its move;
- for an `add`, every source syncing the collection (`load_capabilities`);
- for a `move` or `copy`, also every source syncing the target that binds nothing of the item, or binds it as a pending create alone, each asked there what an `add` of the item carrying its flags needs, the change it pushes being an `Add` (SYNC.md §2);
- for an `add` carrying `supersedes`, also what a `remove` of the superseded item needs, from the sources binding it.

**The producer's gate.** Before it enqueues, a producer SHOULD resolve the capabilities the action needs against the sources concerned. A producer that gates does not enqueue an action a declared source does not support: it reports the capability, the source and its detail, and lets the user change the action. A `partial` support passes and its detail SHOULD be shown. A producer that does not gate enqueues the action as it is, and the owner's backstop parks it when a source concerned does not support it: the gate decides nothing the backstop does not decide again.

**Components.** A calendar collection may refuse a component its server does not store: an events-only calendar (CalDAV's `supported-calendar-component-set`, RFC 4791 §5.2.3), a provider keeping tasks elsewhere. The owner says so with `calendar.component.vtodo` (Annex B), on that collection or source-wide: `none` means the collection takes no VTODO resource, `full` that it does.

It is read only where a row states it, as a capability added after the base set is: a source with no `calendar.component.vtodo` row, declared or not, refuses nothing by it, so a declaration written before it still passes every task.

The owner's backstop and the producer's gate read it, beside the base set, for an `add` or `update` whose new resource is a VTODO and for a `move` or `copy` of one, from the sources concerned in the collection the resource lands in; a `none` refuses the action as an unsupported capability does. A reader offering collections to hold tasks reads it the same way (`load_capabilities`).

**Implementations.** A source declares one implementation per capability, the way its owner performs it there, which the `detail` names when it matters to the user (`by iMIP`). Several implementations of one capability for an account are several sources, among which the user chooses for an intent (below).

An owner holding two for one source exposes them as two sources, or picks one by its own configuration, which is the only way for a state capability, whose effect is a push. An implementation reaching only what its source holds declares the capability on those collections and `none` source-wide.

**Intents.** An intent (Annex B.2) is performed by exactly one source, which its payload names in `source`.

Its candidates are the sources of the account of the collection it anchors the intent on whose row there (the collection's own, or else the source-wide one) has some support (`list_capability_sources`), whether or not the source has synced yet. An intent addressing an item is anchored on the item's collection; one creating a collection on the parent it names, else on a collection of the account and kind the new one takes; one renaming or deleting a collection on that collection.

No candidate is a refusal; one is the performer. With two or more, the performer is the user's choice while it is still a candidate: the latest `set-performer` still queued for the account and capability, read over the store as §15.4 reads a producer's own actions, else the one `load_performer` returns.

Otherwise the producer MUST NOT choose: it refuses, listing the candidates, and the user picks, for this action alone or durably through `set-performer` (§15.3).

**The owner's backstop.** The owner's check is the authoritative one, whatever a producer checked. An action reaching the drain needing a capability (Annex B, `calendar.component.vtodo` included) that a declared source concerned does not support, or an intent whose `source` does not declare its capability, MUST be parked with the capability and the source named in `error`.

## 16. Test vectors

A schema mismatch fails a query; a body named differently, a summary derived differently or a key sorted differently fails nowhere. vectors/ is therefore part of the format:

- **vectors/objects.json**: bodies to their BLAKE3 digests, names and paths (§5), and the RFC 4648 §10 base32 vectors.
- **vectors/summaries.json** and **vectors/fixtures/**: bodies to the `link_id`, summary row, address rows and `sort_key` Annex A produces, the attachment mark read without the body, a message's attachments as its stand-ins name them (Annex A.7), the hedged cases, the encodings that split earlier writers, the charset tables an encoded word is decoded through, the header parses and the line ends of Annex A.1, a field stated twice, the zone resolution of A.3, a resource of overrides alone, the fold and the trim of A.2, and the `alt:`, `hash:`, escaped and minted keys of §9, the fallback of an unusable `UID` among them.
- **vectors/payloads.json**: queue payloads of every action, each with its outcome, valid or malformed against the schemas under payloads/, a known action stating no `v` or one that is no integer among the malformed, or unknown where its action or its `v` names no schema, a known action at `v` 2, an action this part does not define and an application's own among them (§15.2, §15.3).
- **vectors/versions.json**: a store's `format_version` against a program's, each pair with where the store stands by §4.2's order, earlier, the same, later or unknown, the leading zeros of a draft's number, a release's major and a marker the order does not read among them.
- vectors/sync/ and vectors/search/ belong to the other parts; the feed each step of vectors/search/refresh.json leaves (`changed`) binds an owner all the same, a writer's stamps (§4.5) failing nowhere else.

These are the **model vectors**, which §17 binds by profile: objects.json every implementation, since two stores naming bodies differently cannot share a blob directory, and versions.json too, since every profile refuses a store of another version; payloads.json every producer and owner; summaries.json an owner, for each summary kind it writes, the minted, `alt:` and `hash:` keys they give included. A summary vector states a row as the model holds it, its lists (`in_reply_to`, `categories`) as arrays though the store keeps them as rows, and a consumer MUST compare parsed structures, never JSON text. The values are authored from the prose, never from an implementation.

The canonical text alone is bound by checks/: invariants.sh runs the canonical statements through the scenarios this part argues from, and a change to a statement or a rule is checked against it before it lands; schema.sh prepares every statement against the canonical schema and refuses, in the canonical text, a JSON function, a `STRICT` store table or an untyped column (§4.1), and a statement reading `*` or inserting without a column list (§4.4); floor.sh loads the schema on SQLite 3.18, compiles every write into it there and checks a body's name there (§5). checks/rehearsal/ holds migrations that never ship, an additive one, a rebuild and the edit of a `CHECK` (§6), which invariants.sh and floor.sh run on a populated store, each keeping every row and every schema object, beside the rebuild §6 forbids, which does not.

Every file under vectors/ states the version of its format as a top-level `v` and conforms to the JSON Schema of that format under vectors/schema/, which checks/vectors.py validates; an implementation meeting a `v` it does not know MUST NOT read the file as a version it knows. An implementation that vendors vectors/ SHOULD record their digests and re-check them against this repository in its CI, since a frozen copy keeps passing while the format moves.

## 17. Conformance

An implementation conforms to this part by one profile, each holding the one before. It MUST meet every section its row names, keep §4.4's terms for the statements of its directories, each run under its canonical name or its effect reached through statements of its own, and pass the vectors its row names, and MUST state its conformance as each part's version and the profile it meets there, the layers' by SYNC.md §12 and SEARCH.md §12: `storage-draft-15 owner, sync-draft-15 engine, search-draft-15 indexer (canonical)`. One running text of its own for any statement of its directories, or reaching an effect through statements of its own (§4.4), adds `(own statement text)` after its profile: `storage-draft-15 owner (own statement text), sync-draft-15 engine`.

| Profile | What it does | Owes | Statements | Vectors |
| --- | --- | --- | --- | --- |
| reader | opens the store read-only and lists it, holding no lock | §3, §4 (a busy timeout, §4.2's refusals), §6 step 2, §7, §8, §9, §11.1's reads, §12's read, §13, §14's reads of a collection's kind, account, name and role, §14.1 to §14.3's reads, §15.4, §18 | read/ | objects.json, versions.json |
| producer | a reader that enqueues actions, under the staging lock | the reader's, §5, §15.1, §15.3, §15.6's gate and performer, Annex B | read/, queue/ | objects.json, versions.json, payloads.json |
| owner | the one process that mutates the store | every section and both annexes | read/, queue/, owner/ | objects.json, versions.json, payloads.json, summaries.json for each summary kind it writes, the feed each step of search/refresh.json leaves (`changed`, §4.5) |

An engine (SYNC.md §12) is an owner. An indexer and a query client (SEARCH.md §12) are readers, a query client tagging a hit a producer.

## 18. Security considerations

A store holds a person's mail, contacts and calendars. The rules bounding what hostile content costs and keeping a name from becoming a path bind where they are stated: a name checked before a path is built from it and no link followed (§5), a body never replaced and a name held verified before it is kept (§5), a body verified when read (§7), a message's walk and its stand-ins bounded (Annex A.1, §14.3), the search part's expansion and queries bounded (SEARCH.md §7, §8.3). This section states the rest.

- **Modes.** A program creating a store MUST create its directory, objects/, its shard directories and quarantine/ with mode `0700` and every file in them `0600`, index.db, the lock files and SQLite's `-wal` and `-shm` included, as an owner creates local/ and what it keeps there (§3), or on Windows with an ACL granting its own user alone. A program opening a store whose directory or pimdir.db another user can read or write SHOULD refuse it, or open it only once the user confirms.
- **Write access is the trust boundary.** SQLite holds no right per table, so a process that can write pimdir.db can write any row, not the queue's alone: every producer is trusted as the owner is, and the queue is a protocol between trusted processes, never a boundary. An owner MAY ask the user before it performs an intent another process queued (a message sent, an invitation answered).
- **Read access can block.** A lock is taken on a file open for reading, so a process able to read the store directory can hold owner.lock, objects.lock or index.lock and stop the owner, the collector, every producer or the indexer, which the modes above prevent. A lock file MUST be opened without following a symbolic link (`O_NOFOLLOW`, `FILE_FLAG_OPEN_REPARSE_POINT` on Windows), a link there failing the open and naming the store.
- **Names are untrusted.** A file's name (Annex A.7), an attachment's `filename`, a collection's name and a part's section come from content or from a server, and the store keeps them as stated. A program deriving a filesystem path from one, saving an attachment or mirroring a folder, MUST neutralise in it every path separator (`/`, and `\` where the platform reads one), a `.` or `..` component, NUL, every control character (U+0001 to U+001F, U+007F to U+009F) and every bidirectional formatting character (U+061C, U+200E, U+200F, U+202A to U+202E, U+2066 to U+2069), and MUST NOT write outside the directory it chose.
- **Instructions are not content.** A property `X-PIMDIR-` names (Annex B.1's `X-PIMDIR-ONLINE-MEETING`) instructs a performer. A producer enqueuing an `add` or an `update` of a resource the user did not write as it stands (an invitation added to a calendar, an imported file, a resource copied from a message) MUST first remove every such property from it, writing one only as the user asks.
- **No credential in the store.** No program writes a password, a token, a cookie or any other credential into a column of the store or of the index, the opaque ones included (`checkpoint`, `round_cursor`, `round_checkpoint`, `queue.producer`, `queue.error`, `capabilities.detail`, `retained_by`, `bindings.refusal`), and text it records from an error or a remote's refusal MUST first be scrubbed of the credentials it may carry (a URL's userinfo, an `Authorization` header, a token in a query string). This extends §9.2's account, which records none.
- **A store from elsewhere.** A crafted pimdir.db or index.db can carry triggers and views that run with the opening program's functions. A program opening a store it did not create (a copy received, a backup someone else made) SHOULD open both with `PRAGMA trusted_schema = OFF` and `SQLITE_DBCONFIG_DEFENSIVE`, which the canonical schemas and statements run under, each where its SQLite offers it: the pragma from SQLite 3.31, `SQLITE_DBCONFIG_DEFENSIVE` from 3.26. A setting its SQLite lacks is no deviation from this rule. Below 3.31, the 3.18 floor of §4.1 among them, nothing keeps a crafted trigger or view from calling a function the program registers, so such a program SHOULD instead read `sqlite_master` before any other statement and refuse the store when it holds a trigger or a view whose text the canonical schema at the store's version does not create, naming it, and SHOULD register no SQL function with a side effect on the connection. That comparison is made against a version the program knows and against no other: a store above its version (§4.2) holds triggers and views it cannot tell from crafted ones, so below 3.31 a reader or a producer SHOULD refuse such a store it did not create, or open it only once the user confirms, while from 3.31 the pragma needs no comparison and the store opens as §4.2 says. Defensive mode refuses the edit by which a closed vocabulary grows (§6): an owner migrating so leaves it for that migration's transaction alone.
- **Copies and erasure.** A backup holds what the store holds, quarantine/ included (§8), and takes the store's modes. A purge leaves a row's bytes in the database files until the procedure of §11.5 erases them, which reaches no backup, no filesystem snapshot and not quarantine/, which only the user empties (§7).

## Annex A. Summaries (normative)

What a writer derives from an item before its row reaches the store: the identity hint §9 keys on, the row of the kind's summary table with its list rows, the `item_address` rows and the `sort_key` (§9.3). The store parses no body; the schema fixes the columns and vectors/summaries.json the values.

A summary holds what a list row shows, what it sorts by and what the store's own references read (§14.2). A question about an item's content, its text, its calendar time across a series or whether it holds a property, is the search part's (SEARCH.md), and no column is added to answer one.

This annex is at **revision 3**. A change to what a writer derives from a body bumps it, in a minor version of this part, and says which columns it changed; `store_meta.derivation` records the revision a store's rows stand under, an owner at a later one re-deriving those columns and one at an earlier one recording its own (§6).

Revision 3 fixed how a message's header and the lines of a message are read (A.1), changing the `mail_summary` columns read from a header field (`message_id`, `in_reply_to`, `subject`, `sender`, `sender_name`, `date`), a message's address rows and the `sort_key` read from its `date`, re-derived from every held message. A link id is never re-derived (SYNC.md §6). It also moved a zoned calendar time a transition skips (A.3), a `sort_key` §13 exempts from byte identity, restated when the item is next derived. And it bounded the walk of a message's parts (A.1), so a message nested deeper or split into more parts than the bounds marks, invites and is stood for (§14.3) only by what the walk reads.

A derivation is made from the body, or from a server-side summary (an IMAP `ENVELOPE`, a Graph `$select`, Gmail's metadata, a JMAP `Email/get`) where the kind has a cheap tier. A value such a summary serves raw, as the content carries it, is derived by this annex's rules and MUST then agree with the body's derivation byte for byte, the attachment mark, the size and the invitation aside. A value a server decodes or parses by rules of its own is no derivation of this annex: it stands until the body is read, which replaces it (A.1).

A message's `subject`, `date` and `sender` are the exception a store cannot wait for the body on: §9 compares them, byte for byte, before any body is read, to tell a message from another reusing its `Message-ID`. They are therefore read raw wherever the source serves them raw (A.1 names each protocol's read, SYNC.md §4 binds a connector to it), and a member named from a decoded value where it serves none may be kept apart from its own message, a missed dedup (§9).

### A.0 Common rules

- **Decoded**: RFC 2047 words and RFC 2231 parameters decoded, vCard and iCalendar text unescaped (RFC 6350 §3.4, RFC 5545 §3.3.11), lines unfolded; a message's header fields as A.1 reads them. A property splits on the first unquoted colon (RFC 6350 §3.3).
- **Verbatim**: the value bytes as the body carries them, unfolded.
- Bytes that are not well-formed UTF-8 are replaced, never refused: each maximal subpart of an ill-formed sequence becomes one U+FFFD, the practice of Unicode §3.9 that the WHATWG Encoding Standard's UTF-8 decoder follows. `caf` and the byte `E9` read `caf�`; `F0 9F 98` before a space, a truncated sequence, one `�`; `C0 AF` and `ED A0 80`, an overlong form and a surrogate, one `�` a byte.
- A `NOT NULL` column is `''` when the property is absent; every other column is `NULL` when absent or not examined, unless the kind says otherwise.
- An instant is RFC 3339 UTC at seconds precision with the `Z` designator.

### A.1 `message/rfc822`

| Column | Derivation |
| --- | --- |
| `message_id` | the first msg-id of `Message-ID` (RFC 5322 §3.6.4), bare, read as below; `NULL` when absent or unparseable |
| `in_reply_to` | the `In-Reply-To` ids, bare, read as below, in document order, one `mail_in_reply_to` row each, `position` from 0; none when absent |
| `subject` | `Subject`, decoded as an unstructured value (below); `''` when absent |
| `sender` | the first `From` address, canonical (A.6) |
| `sender_name` | its display name (below); `NULL` when it has none |
| `date` | `Date` as an instant, read as below; `NULL` when absent or unparseable. From a server-side summary, the `Date` field the server states (IMAP `ENVELOPE`'s, Graph's `sentDateTime`, JMAP's `sentAt`), never a received date |
| `size` | with the body, its octets; without it, the size the source states (IMAP's `RFC822.SIZE`, Graph's `PidTagMessageSize`, Gmail's `sizeEstimate`, JMAP's `size`), which may be an estimate, `NULL` when it states none |
| `attachment` | with the body, `1` when a part the walk reads makes the attachment mark (below), `0` when none does; without it, the source's own flag where it states one (Graph's `hasAttachments`, JMAP's `hasAttachment`), else `1` when the top-level `Content-Type` is `multipart/mixed` and `0` otherwise |
| `invitation` | with the body, the first `UID` of the first `text/calendar` part in document order (an iMIP message, RFC 6047), its transfer encoding undone and its lines unfolded, the value verbatim; `NULL` when no part is one, when that `UID`'s line is longer than 65,536 octets once unfolded, which no writer reads, and without the body |

The size and the mark read without the body are replaced by the body's own once it is read, and a writer holding the body MUST NOT write either read without it over it. A row whose body was released (§11.4) holds it no more, and the next meta restates both.

A placement gaining a body the account already holds, linked rather than read (an upgrade linking from the store, SYNC.md §6, a copy, a move, a second label), holds that body as read. Its `size` is the body's octets, and its mark and invitation those a row holding the body states (`held_mail_summary`), never those its listing read without it.

A writer reading the body as it streams, never whole, derives the mark and the invitation as the whole body gives them, the parts walked and decoded alike in one pass. One recording attachments states them from the walk that finds its stand-ins (§14.3).

**Lines.** A line of a message, in a header block or a multipart body, ends at CRLF, at a bare LF or at the end of the message. One `\r` just before the end of the message is the line break's, never the line's content: a header line or a delimiter ending there ends before it, so a closing delimiter cut between its `\r` and its `\n` (`--b--\r` last) still closes its multipart. Any other `\r` not followed by a LF is the line's content: a header line holding one before its CRLF (raw `\r\r\n`) is no empty line, and the header block goes on past it. Content read as octets, an entity's body decoded or measured, keeps every octet.

**The walk of a message's parts** reads its entities in document order, a multipart before its children: the message's own entity at depth 0, a multipart's children one deeper (RFC 2046 §5.1), a `message/rfc822` part one entity whose own parts it does not open. A multipart no closing delimiter ends is closed by the end of the entity holding it, as a closing delimiter standing there would close it: what follows its last delimiter line is its last child, a part as any other, the line break the entity ends with being the missing delimiter's (RFC 2046 §5.1.1), so a message cut short derives what the same message closed does. An entity's `Content-Type`, `Content-Disposition`, `Content-Transfer-Encoding` and `Content-ID` are read as a header field is (below), from their first occurrence when one is stated twice. It reads no entity deeper than 64, and none after the 10,000th it has read, the message's own counted: an entity left unread, with every part under it, makes no mark, no invitation, no stand-in (§14.3) and no text the search part extracts (SEARCH.md §6), so every writer derives the same columns from a hostile message by a bounded walk.

**The attachment mark** is made by a part the walk reads that is disposed as an attachment: its `Content-Disposition` type is any but `inline`, `attachment` or one RFC 2183 §2.8 has a reader take as `attachment`. A part stating no disposition makes it when it is sent bare as a file: its media type is neither `multipart/*` nor `text/*`, and it carries no `Content-ID`, a part a `Content-ID` names being a resource a body shows (RFC 2392), not a file. Three entities never make it, whatever they state: the message's own entity when it is a multipart, which no section names; every child of a `multipart/encrypted`; every child but the first of a `multipart/signed`. The last two are the protocol parts of RFC 1847, a key's control data and a signature, which nobody attached. The disposition type is the field's value up to its first `;`, trimmed, compared ignoring ASCII case, a field holding none stating no disposition; the media type is the `Content-Type` value up to its first `;`, trimmed and lowercased, `text/plain` when the field is absent, under a `multipart/digest` too, or when the value holds not exactly one `/` (RFC 2045 §5.2). The parts of a protocol part, if it holds any, are walked as any other.

The invitation, a fact of an immutable message, is never cleared once read: `upsert_mail_summary` keeps a known one over `NULL`, released body or not.

The mark misses both ways, each corrected when the body is read: a `multipart/mixed` with no attachment (a list footer, inline images) reads as one, an attachment under `multipart/signed` or `multipart/encrypted` as none. It saves an IMAP listing the `BODYSTRUCTURE`.

**Hint**: `message_id`, else `alt:` followed by the decoded subject, the `date` column and the `sender` column joined by `|`, each empty when absent (`alt:Stand-up notes|2026-08-01T10:00:00Z|alice@example.org`). **Addresses**: every `From`, `To`, `Cc`, `Bcc` under its role, in document order. `References` is the search part's (SEARCH.md §9). **`sort_key`**: the `date` column, or `''`; read descending.

**Reading the header.** The identity and the `alt:` key are built from these parses, so every writer MUST read a header as follows.

- The header block ends at the first empty line, its lines ending as **Lines** says (above). A field is unfolded by removing every line break followed by a space or a tab, the whitespace kept (RFC 5322 §2.2.3). An unfolded line splits at its first colon into a name and a value: the name is the bytes before it, trimmed of trailing whitespace, which RFC 5322 §4.5's obsolete syntax allows between a name and its colon (`Message-ID :` is `Message-ID`), and a line holding no colon is no field. A name is matched without regard to ASCII case, and a field present twice is read from its first occurrence, in document order, whichever column reads it. Its value, the bytes after the colon, is read as UTF-8 (RFC 6532), replaced as A.0 says.
- A **comment** is text in parentheses, nested, in which a backslash quotes the next character; a **quoted-string** is text in double quotes, holding no comment, in which a backslash quotes the next character (RFC 5322 §3.2). Where a rule below removes comments, each reads as one space.
- Whitespace is the space and the tab.

**An unstructured value**, `Subject` and a display name, is decoded in three steps:

1. Every RFC 2047 encoded word, wherever it stands, is replaced by its text: `=?`, a charset (an RFC 2047 token, a `*` and an RFC 2231 language dropped from it), `?`, `B` or `Q` in either case, `?`, one or more printable ASCII characters other than `?`, and `?=`. `B` is base64 (RFC 4648 §4), its trailing `=` optional; `Q` is RFC 2047 §4.2's, `_` a space and `=` with two hexadecimal digits of either case one octet. The octets are decoded in the charset when its name, matched without regard to ASCII case, is a label of the WHATWG Encoding Standard naming an encoding other than its replacement encoding, by that encoding's decoder, with no byte order mark sniffed: `iso-8859-1` and `us-ascii` so name windows-1252, where the octet `80` is the euro sign, and a legacy charset is read through its index (ISO-8859-2, KOI8-R, ISO-2022-JP, GBK and the rest), which a writer therefore carries. The labels, the indexes and the decoders are those of the Encoding Standard as last updated on 19 October 2026, its commit snapshot be17ac5c49881336538acfc7b40dba3c8009144b; a writer on a later one reads every label and octet sequence that snapshot defines as it does. A word whose charset is no such label, a `B` word holding a character outside the alphabet, an `=` anywhere but in a trailing padding of at most two, or a length, padding aside, leaving one character beyond whole groups of four, and a `Q` word holding an `=` not followed by two hexadecimal digits are malformed, and each stays as its literal text.
2. Whitespace standing between two decoded words, and nothing else, is removed (RFC 2047 §6.2); all other whitespace stays.
3. Whitespace is trimmed from both ends; whitespace inside, a tab included, stays as it is.

**A display name** is the text of a mailbox before its `<`, its comments removed, each quoted-string replaced by its content with its quoted pairs undone, then decoded as an unstructured value; a mailbox with no `<` has none, and an empty one is none. An address list splits at the commas outside a quoted-string, a comment and angle brackets, a group listing its own mailboxes, its name, colon and closing `;` dropped. A mailbox's address is the text between its angle brackets, else its whole text with its comments removed, trimmed, then made canonical (A.6).

**`Message-ID`** names the field's first msg-id. Read from its start, comments are skipped; at the first `<` outside one, the id is the text up to the next `>`, trimmed, and the field is unparseable when no `>` follows or that text is empty. A field with no such `<` is read bracketless: its comments removed and trimmed, it is the id when it holds no whitespace, no `<`, `>` or `"`, and exactly one `@`, and unparseable otherwise. An id keeps its case and is compared byte for byte. **`In-Reply-To`** lists every msg-id of the field read the same way, each `<` outside a comment to the next `>`, empty ones dropped; a field with no such `<` lists, its comments removed, each of its whitespace-separated words a bracketless `Message-ID` would take.

**`Date`** is the `date-time` of RFC 5322 §3.3 with the obsolete forms of RFC 5322 §4.3; any other value is unparseable.

- Comments are removed. The text up to and including the first comma, when there is one, is the day of the week, skipped and never checked against the date.
- What remains is five words separated by whitespace, whitespace around a colon not counting: the day, one or two digits; the month, `Jan` to `Dec` without regard to case; the year, two digits or more; the time, `hh:mm` or `hh:mm:ss`, two digits each; the zone. Nothing follows them.
- A two-digit year below 50 is in the 2000s, one of 50 or more and a three-digit year in the 1900s (`26` is 2026, `96` 1996, `126` 2026). The year is then 1900 to 9999 (RFC 5322 §3.3).
- The zone is `+` or `-` and four digits `hhmm`, `mm` at most 59, `-0000` reading as `+0000`; or, without regard to case, `UT` and `GMT` at `+0000`, `EDT` at `-0400`, `EST` and `CDT` at `-0500`, `CST` and `MDT` at `-0600`, `MST` and `PDT` at `-0700`, `PST` at `-0800`; or one letter other than `J`, a military zone, which RFC 5322 §4.3 reads as `-0000` and so at `+0000`. A missing zone, or any other, is unparseable.
- The day exists in its month and year (29 February in a Gregorian leap year alone), the hour is 00 to 23, the minute 00 to 59 and the second 00 to 60, a leap second's 60 read as 59. Anything out of range, `30 Feb` and `24:00` among it, is unparseable, never carried into the next day or month.
- The instant is the stated time less the zone's offset, written as A.0 writes one; one past the year 9999 is unparseable.

**A server-side summary** agrees with the body (above) where it serves the field raw: a header field fetched as such (IMAP's `BODY.PEEK[HEADER.FIELDS (…)]`, Gmail's metadata headers, JMAP's `header:…:asRaw:all`, Graph's `internetMessageHeaders`), and the date, subject and message-id strings of an IMAP `ENVELOPE`, each read by the rules above. A source listing every occurrence of a field is read from the first, as the body is: JMAP's `header:Subject:asRaw:all`, first element, never `header:Subject:asRaw`, which answers the last occurrence; the first entry of that name in Gmail's metadata headers and in Graph's `internetMessageHeaders`. A value the server decodes or parses itself (JMAP's `subject`, `sentAt` and `from`, Graph's `subject`, `sentDateTime` and `from`, an `ENVELOPE` address's name) need not agree. A writer holding the body MUST NOT write such a value over the body's, as for the size and the mark. A link id derived from one is kept once resolved (SYNC.md §6) and may differ from the key a raw reading gives, a missed dedup (§9), so a writer SHOULD read the fields of the hint raw, as a connector MUST read the three a member is compared by (SYNC.md §4).

**The fields §9 compares are read raw.** `subject`, `date` and `sender` decide whether a member lands a create, joins an item, revives a row, links a body, shares a `seq` (§9, SYNC.md §6), so they are derived by the rules above from the raw `Subject`, `Date` and `From` wherever the source serves them (SYNC.md §4): on IMAP the `ENVELOPE`'s subject and date strings and the `From` field fetched as a header field, an `ENVELOPE` address being the server's parse; on Gmail the metadata headers; on JMAP `header:Subject:asRaw:all`, `header:Date:asRaw:all` and `header:From:asRaw:all`, first element; on Graph `internetMessageHeaders`. A source serves nothing raw where it states the field decoded alone: Graph answers `internetMessageHeaders` only to a request selecting it, on a listing, a delta page and a single read alike, and for the messages it holds header fields for, received and sent, which a draft never handed over may not be; a member it answers none for is named from `subject`, `sentDateTime` and `from`, values of the server's own making. A summary so named agrees with a row another reading wrote only where the two happen to coincide: elsewhere the member is kept apart from its own message, a missed dedup (§9), until its body is read, which restates its row and never its key.

A raw field carried inside JSON (JMAP, Gmail, Graph) holds text, never octets: the agreement above is owed for a field whose bytes are well-formed UTF-8, and one holding other octets reads as its server rendered them, a value of the server's own making.

### A.2 `text/vcard`

| Column | Derivation |
| --- | --- |
| `uid` | `UID` verbatim |
| `fn` | `FN`, decoded; `''` when absent |
| `kind` | `KIND` lowercased (`individual`, `group`, `org`, `location`) |
| `org` | the first component of the first `ORG`, decoded |

**Hint**: `uid`, else `hash:` followed by the sixteen lowercase hexadecimal digits of the FNV-1a 64 digest of the bytes. A card resolves at `Full` only, carries no flags (a known-empty set), and is mutable: its revision moves while its key does not. **Addresses**: every `EMAIL` under `email`, canonical, with no name. **`sort_key`**:

`fn` lowercased by the default full lowercase mapping of Unicode 15.0.0 (UnicodeData.txt and the unconditional mappings of SpecialCasing.txt; Rust's `str::to_lowercase`, Java's `toLowerCase(Locale.ROOT)`), locale-independent, then trimmed; read ascending, a nameless card first. Of SpecialCasing.txt's conditional mappings Final_Sigma applies and no other, the language-sensitive ones included: a capital sigma ending a word (U+03A3, in the context Unicode §3.13 defines) maps to the final form U+03C2, as both runtimes map it, and to U+03C3 elsewhere. The trim removes, from both ends, the characters of the White_Space property of Unicode 15.0.0 (U+0009 to U+000D, U+0020, U+0085, U+00A0, U+1680, U+2000 to U+200A, U+2028, U+2029, U+202F, U+205F and U+3000), a no-break space among them, and nothing inside.

A writer on a later Unicode version maps every character 15.0.0 assigns as 15.0.0 does, the case pairs being stable across versions. A character assigned later, which no vector holds, MAY map as the writer's version says, a missed seek or a mis-sort being the cost.

### A.3 `text/calendar`, `VEVENT`

**The item is the calendar object resource.** RFC 4791 §4.1 keeps the components sharing a `UID` in one resource, so a series and its `RECURRENCE-ID` overrides are one item, one blob, one key, and an override is a body edit. A connector to an instance-granular source MUST reassemble the set. A resource holds one component type, so its summary is one row in that type's table:

`event_summary`, `task_summary` (A.4) or `journal_summary` (A.5). A component with no table (`VFREEBUSY`, `VAVAILABILITY`) is an item with a body and no summary. A second resource under one `UID` is minted and kept (§9).

| Column | Derivation |
| --- | --- |
| `uid` | `UID` verbatim, of the component the row is read from (below) |
| `summary` | `SUMMARY` of the master (no `RECURRENCE-ID`), decoded; `''` when absent |
| `location` | `LOCATION`, decoded |
| `dtstart`, `dtstart_tzid`, `dtstart_value` | `DTSTART` verbatim, its `TZID`, and `date-time` or `date` |
| `dtend` | `DTEND` verbatim; a `DURATION` is not resolved |
| `recurring` | `1` with an `RRULE` or `RDATE` on the master, `0` when looked and none, `NULL` when not looked |
| `until` | the `RRULE`'s `UNTIL` verbatim |

**The component the row is read from** is the master: the first component of the resource's type carrying no `RECURRENCE-ID`, in document order. A resource holding overrides and no master, as an attendee invited to one instance of a series stores it, is read from the first component carrying a `RECURRENCE-ID`, in document order, which stands for the master in every rule of this section and of A.4 and A.5: it states the `uid`, the summary, the location, the times, the addresses and the `sort_key`. `recurring` and `until` read it too, so an override stating no `RRULE` and no `RDATE`, as RFC 5545 has it state none, gives `recurring` `0` and `until` `NULL`: the row says what the resource holds, one instance, and the series is the search part's to place (SEARCH.md §7).

Times are verbatim with their parameters, never resolved: a reader with a time zone database re-derives an instant, one without displays the wall time. The one resolved projection is the `sort_key`. **Hint**: `uid`, else `hash:` on A.2's terms; mutable, no flags. **Addresses**: `ORGANIZER` and every `ATTENDEE` under their roles, `mailto:` stripped, canonical, the `CN` parameter as the name.

**`sort_key`**: the master's `DTSTART` as an instant, read ascending.

A UTC date-time is taken as is. A zoned one, carrying a `TZID`, resolves through the first of these that names its `TZID`, matched byte for byte: the resource's own `VTIMEZONE`, then the IANA time zone database, which a resource may lean on in place of a `VTIMEZONE` (RFC 7809); a `TZID` neither names reads as floating. A `VTIMEZONE` observance's `RRULE` is followed for at most 1,000,000 periods from its `DTSTART`, a period counted as SEARCH.md §7 counts one, the offset of the last onset found standing beyond them, so a hostile rule costs every writer one bounded walk and gives one key.

A wall time a transition makes ambiguous or skips takes the UTC offset in effect before the transition (RFC 5545 §3.3.5): of an ambiguous one the earlier instant, and a skipped one read at the offset before the gap, so `DTSTART;TZID=America/New_York:20260308T023000` is `2026-03-08T07:30:00Z`, 03:30 on the clock that day. A date-only value reads as `T00:00:00Z`; a floating date-time reads as UTC.

A series keys on its first occurrence, which `until` bounds for a reader that must expand it (SEARCH.md §7). Nothing parseable keeps `''`.

### A.4 `text/calendar`, `VTODO`

`task_summary` carries `uid`, `summary`, `dtstart` with its parameters, `recurring` and `until` on A.3's terms, and:

| Column | Derivation |
| --- | --- |
| `due`, `due_tzid`, `due_value` | `DUE` verbatim, its `TZID`, and `date-time` or `date` |
| `status` | `STATUS` uppercased verbatim |
| `completed` | `COMPLETED` verbatim |
| `percent` | `PERCENT-COMPLETE` as an integer |
| `priority` | `PRIORITY` as an integer, 0 to 9 (RFC 5545 §3.8.1.9); `NULL` when absent or out of range |
| `categories` | every `CATEGORIES` value in document order, each property's list split on unescaped commas and decoded, empty values dropped, one `task_category` row each, `position` from 0; none when absent |
| `parent` | the value of the first `RELATED-TO` whose `RELTYPE` is `PARENT` or absent (RFC 5545 §3.2.15), verbatim |
| `mid` | the message the first `ATTACH` or `URL` holding a `mid:` URI (RFC 2392) names: its message-id part, before any `/`, percent-decoded, bare |
| `created` | when it was captured: `CREATED` as an instant on A.3's rules, else `DTSTAMP` as one (both UTC, RFC 5545 §3.8.7.1, §3.8.7.2); `NULL` when neither reads as one |

An `X-` property is the body's alone: no column carries one, and a client reads it from the body.

**Addresses**: A.3's, and every `CONTACT` (RFC 5545 §3.8.4.2) under `contact`, in document order. Its address is the one its `ALTREP` names when that is a `mailto:` URI, else its text, canonical either way (A.6); its name is its text decoded, `NULL` when the address was read from a text that is an addr-spec. A `CONTACT` with an empty text and no such `ALTREP` files no row.

**`sort_key`**: `DUE`, else `DTSTART`, as an instant on A.3's rules (RFC 5545 §3.8.2.3); `''` when neither.

### A.5 `text/calendar`, `VJOURNAL`

`journal_summary` carries `uid`, `summary` and `dtstart` with its parameters on A.3's terms. **`sort_key`**: `DTSTART` as an instant, or `''`.

### A.6 Addresses

`item_address` holds every person an item names, one row per address per role, in document order within the role: `from`, `to`, `cc`, `bcc` for mail, `email` for a card, `organizer` and `attendee` for a calendar object, and `contact` for a task (A.4).

The **canonical address** is the addr-spec alone, display name, comments, angle brackets and `mailto:` removed, lowercased whole by A.2's mapping, so `İ` becomes `i` and a combining dot above. A value that is not an addr-spec is kept lowercased as it is. The **name** is the display name decoded (a mail phrase, an `ATTENDEE`'s `CN`, a `CONTACT`'s text), or `NULL`; a card's addresses have none.

### A.7 `application/octet-stream`

A file's bytes say nothing about it, so its summary is what its source or its writer states, not a derivation from the body.

| Column | Derivation |
| --- | --- |
| `name` | the file's name in this collection, as its folder or source states it, or an attachment's `filename` (`Content-Disposition`, else the `Content-Type` `name`, RFC 2231 and RFC 2047 decoded, an RFC 2231 value whose charset is no label A.1 decodes read as UTF-8, replaced as A.0 says); `''` when none |
| `media_type` | the type and subtype as stated (an attachment's `Content-Type`), lowercased, parameters dropped; `NULL` when unstated |
| `size` | with the body, its octets; without it, as stated: an attachment's decoded octets (its body with its `Content-Transfer-Encoding` undone, the line break before the next delimiter belonging to the delimiter, RFC 2046 §5.1.1; `NULL` for a `multipart` part), or the source's figure |
| `part` | for an attachment, its section in the message's body (RFC 3501 §6.4.5, `1`, `2.1`), counted on the body as stored; `NULL` otherwise |

The size read without the body is replaced by the body's own, as for mail (A.1). **Hint**: none, the bytes stating no identity.

An attachment is keyed `part:`, its message's `link_id`, `#` and its `part` (`part:abc@host#2`), so every writer walking one message names its files alike. A file created in the store is keyed `file:` and 32 lowercase hexadecimal digits of 128 random bits. Neither is a protocol identity, nor parsed by a reader.

A file a source lists is keyed by the id its server keeps across a rename and a move, which is also its handle (SYNC.md §4). A file carries no flags (a known-empty set) and no addresses. **`sort_key`**: `name` on A.2's rule for `fn`, read ascending.

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

A **flag change** is a flag a `set-flags` adds or removes against the item's current set, or one an `add` or `copy` carries into the collection, whose set starts empty there: a `set-flags` restating a flag needs nothing for it, a draft added with `\Draft` needs `mail.flags.draft`. A `set-flags` stating `base` is read the same way, against the current set and never against `base`: what it changes is what the set §15.3 has it leave holds and the current set lacks, or the reverse, so a flag it adds that a sync landed meanwhile needs nothing.

A flag names its capability compared without regard to ASCII case, as IMAP compares flags and keywords (RFC 9051 §2.3.2), so `$important` is `$Important`. A change on `$Important` or `$Junk` needs `mail.flags.important` or `mail.flags.junk` from a source stating a row for it, `none` included, and `mail.flags.keywords` from one stating none: a source carrying these two as fields of its own while taking no arbitrary keyword (Gmail's `IMPORTANT` and `SPAM` labels, Graph's `importance`) supports them without `mail.flags.keywords`, and a declaration written before them reads as it did.

A resource is **scheduled** when one of its components names an `ATTENDEE` and some `ORGANIZER` or `ATTENDEE` of that component lacks `SCHEDULE-AGENT=CLIENT` or `SCHEDULE-AGENT=NONE` (RFC 6638 §7.1). A source supporting `calendar.scheduling` notifies the attendees of what it pushes (RFC 6638 §3.2).

An `add` or `update` **asks for an online meeting** when its new resource carries `X-PIMDIR-ONLINE-MEETING:TRUE` on a component the current one does not. A source supporting `calendar.online-meeting` creates an online meeting of its provider with the resource and removes the property, the join details arriving with the next sync as `CONFERENCE` (RFC 7986 §5.11). The property is an instruction, never content: §18 says who may write it.

A scheduled resource for a source without `calendar.scheduling` is parked by the owner's backstop, and a producer that gates refuses it, unless the user accepts that nobody is notified. A producer recording that acceptance MUST write it into the resource as `SCHEDULE-AGENT=NONE` on every `ORGANIZER` and `ATTENDEE` of the component lacking `SCHEDULE-AGENT=CLIENT` or `NONE`, never as a flag of its own: the resource is then not scheduled, the parameter living in it, so the gate and the backstop read the same answer, and a source that schedules leaves the attendees so marked alone.

An implementation notifying by email (RFC 6047) rather than through the server marks them `CLIENT` on what it pushes, so the server does not notify them again.

An update **changes an occurrence** when the components carrying `RECURRENCE-ID` differ between the current and the new resource, `DTSTAMP` and `LAST-MODIFIED` aside.

### B.2 Intents

Performed by the source the payload names (§15.6), outside the store, then acknowledged with `cancel_action` and its receipt (§15.5) or parked. Of the intents below, `submit` alone can end with its outcome unknown and is then parked `unconfirmed: ` (§15.2), a message handed over twice being two messages; every other is performed again when its outcome is unknown, a repeat finding its effect made or restating it. An intent addressing an item does so by `seq`, or by `link_id` when the item is still a pending `add` the producer queued, exactly one of the two. Its payload is typed and refused as §15.3 says, a performer parking what its producer should have refused.

| Action | Payload at `v: 1` | Performed as |
| --- | --- | --- |
| `submit` | `{ "v": 1, "source": id, "from": addr, "rcpts": [addr…], "subject": text?, "copy": collection? }`, the message as the action's body | the message sent with `from` and `rcpts` as its envelope, its `Bcc` field removed before transmission (RFC 5322 §3.6.3); anchored on the collection its sent copy belongs to, `subject` for reports only; with `copy`, a copy filed in that collection once sent |
| `calendar-reply` | `{ "v": 1, "source": id, ( "seq": n \| "link_id": key ), "partstat": "ACCEPTED" \| "TENTATIVE" \| "DECLINED", "comment": text?, "recurrence_id": text? }` | the account's reply sent to the item's organizer, `comment` with it (RFC 5546 §3.2.3), for the one occurrence `recurrence_id` names when present; the new `PARTSTAT` arrives with the next sync |
| `calendar-cancel` | `{ "v": 1, "source": id, ( "seq": n \| "link_id": key ), "comment": text?, "recurrence_id": text? }` | an event the account organises cancelled, the attendees notified with `comment` (RFC 5546 §3.2.5), only the occurrence `recurrence_id` names when present; the removal, or the series without that occurrence, arrives with the next sync |
| `collection-create` | `{ "v": 1, "source": id, "name": label, "parent": collection? }` | a collection named `name` created on the source's server, under `parent` when present, of the anchor's kind; it arrives with the next sync |
| `collection-rename` | `{ "v": 1, "source": id, "name": label }` | the collection the action is queued on renamed `name` on the source's server, its parent and its items kept; the new name arrives with the next sync |
| `collection-delete` | `{ "v": 1, "source": id }` | the collection the action is queued on deleted on the source's server, with the items it holds; the deletion arrives with the next sync |

A `submit` naming `copy` needs `mail.submit.copy` beside `mail.submit`, from the same performer.

A performer whose provider files the sent message itself (Graph's `sendMail`, Gmail) supports it as that filing and enqueues nothing. Any other files the copy as an `add` of the message into `copy`, `\Seen` set, by replacing the intent (§15.5), which the sources syncing `copy` then push. A provider filing every sent message, asked or not, says so in the `detail` of `mail.submit`.

A producer asks for `copy` only of a declared performer, and against an undeclared one files the copy itself, an `add` beside the `submit`.

`calendar.reply` and `calendar.cancel` address an item and are anchored on its collection (§15.6). An implementation through the provider's own verbs reaches only the items its source holds, and is declared on those collections.

One over email (RFC 6047), sending the iTIP object (RFC 5546) with `METHOD:REPLY` or `METHOD:CANCEL` and the comment as `COMMENT`, reaches any item and is declared source-wide by a source that sends. It also writes the account's new `PARTSTAT` into the item, or removes it, marked `SCHEDULE-AGENT=CLIENT`.

A source that schedules on the server and has no verb for them MAY perform them as the write its server schedules from, a `PARTSTAT` change or a removal, and declares them `partial` when `comment` is lost.

`recurrence_id` names one occurrence of a recurring item by its `RECURRENCE-ID` (RFC 5545 §3.8.4.4), the value as the item's iCalendar spells it, parameters aside: the original start of the occurrence, a date or a date-time in the form of the series' `DTSTART`, the `Z` kept when it is UTC.

It names an overridden component of the item or an instance its recurrence rule generates; absent, the intent addresses the whole series. The reply carries the `RECURRENCE-ID` (RFC 5546 §3.2.3). The cancel notifies the attendees of that instance alone (RFC 5546 §3.2.5) and leaves the series without it, an `EXDATE` added or the overridden component cancelled. A performer that finds no such occurrence in the item parks the row.

It is read beside the intent, as `copy` is beside `submit`: a payload naming it needs `calendar.reply.occurrence` or `calendar.cancel.occurrence` from the same performer. A producer names it only to a declared performer.

`collection.create` addresses no item. It is anchored on `parent` when the payload names one, else on a collection of the account and the kind the new collection takes, so a source refusing children under one collection declares `none` on that collection alone (an IMAP mailbox marked `\Noinferiors`).

`parent` is a collection of the anchor's account and kind that the performer syncs. `name` is one level of the hierarchy, a non-empty label carrying no separator of the provider, mapped by the performer onto its server: an IMAP mailbox under the parent's name with the server's delimiter, a Gmail label nested as the parent's, a DAV collection with that display name in the home set or under the parent.

The performer acknowledges the intent once the server holds the collection; one already holding a collection of that name under that parent is a success, the intent being at least once (§15.5).

The collection reaches the store with the next sync of the performer, under the id its owner gives it (§9.2) and with `name` as its label, which is how the producer recognises it. A source whose implementation cannot create collections declares `none`, its `detail` saying so.

`collection.rename` and `collection.delete` address the collection the action is queued on, the anchor, which the payload does not restate, so a rename of the collection in the store (§14) leaves the row addressing it. It is a collection of the account that the performer syncs. A source keeping a collection fixed (an IMAP `INBOX`, a provider's system folder or label, a default calendar) declares `none` on that collection alone.

A rename changes the collection's label alone. `name` is one level of the hierarchy, as for `collection-create`, and the collection keeps its parent, a move under another parent being no rename. A performer finding a sibling already named `name` parks the row, and one finding the collection already so named acknowledges it, the intent being at least once (§15.5).

The new name reaches the store with the next sync of the performer, as a rename another client made on that server does. Where the owner derives the collection's id from its name (an IMAP mailbox's), the performer SHOULD follow the rename in the store with `rename_collection` (§14) when it acknowledges the intent, so the items keep their bindings rather than leaving under the old id and arriving under the new one.

A delete removes the collection and the items it holds, and never another collection. A performer finding a collection under it on the server parks the row naming them, deleting nothing: a server deleting the children with it (Graph) would remove what nobody named, and one refusing (an IMAP server, a JMAP `mailboxHasChild`) would leave the request half done. The person deletes the children first. The performer acknowledges the intent once the server no longer holds the collection, one already gone being a success.

The deletion reaches the store with the next sync of the performer, as a deletion another client made on that server does. The store removes no item for it and queues no `remove`: whether another source mirroring the collection loses it too is SYNC.md §5's rule on deleting a collection, which only an engine's configuration enables.
