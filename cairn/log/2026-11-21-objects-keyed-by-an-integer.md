---
cairn: log
change: objects-keyed-by-an-integer
landed: 2026-11-21
---

# Objects keyed by an integer

storage-draft-15 and search-draft-16, neither tagged, so both are edited in place and no number moves (sync-draft-15 likewise, for the three column names its projection reads). The owner's decision of 2026-11-21 on item 2 of cairn/changes/the-write-path-before-the-freeze (the measurements are in its prototypes-2026-11-21.md: about 60% fewer SQLite bytes a message and pimdir.db 29% smaller on the write side, a text term's placements read in 74 ms against 477 at 517k for `enron` on the read side). This lands the spec side; io-pimdir follows.

## Rules and the check guarding each

- **An object is keyed by an integer** (STORAGE §4.3, §13, migrations/storage/0001_init.sql): `objects.id INTEGER PRIMARY KEY AUTOINCREMENT`, drawn at insert above every id drawn before and never reused; the BLAKE3 name stays on the row alone, unique by `objects_by_hash`, and still names the blob file (§5 and §16 unchanged). Guard: checks/invariants.sh "objects: an id is drawn above every id drawn before, the collected ones' included, and a body stored again keeps its own"; checks/rehearsal/populate.sql now deletes its last object too, and run.sh checks the next object id after each rehearsed migration, so a migration must keep the third sequence.
- **Every pointer at a body is the object's id** (STORAGE §4.3, §5, §13): `items.object` (was `object_hash`), `items.conflict_object`, `bindings.base_object`, `bindings.conflict_object`, `bindings.shared_object` and `queue.object` (was `object_hash`) are INTEGER, typed by CHECK, each a foreign key onto `objects(id)`; the six pointer indexes are on those integers, so a new body's entries land at their end, and `objects_by_hash` is the one index keyed by a name. Refcounts (§5), `recompute_refcounts`, `collection_holds_objects`, the release (§11.4), retention and the collector follow, joining ids. Guard: invariants "objects: every pointer at a body is a foreign key onto objects.id, and a pointer holding a name is refused"; "schema: an object's delete checks every pointer at it on its index" (now `DELETE ... WHERE id = 1`), and the same in checks/floor.sh on 3.18.2.
- **A body is named by its hash** (STORAGE §4.4, new paragraph; GUIDE §5 step 3): no canonical statement takes or answers an object's `id`. A write takes the hash and stores the id (`insert_item`, `update_item`, `insert_binding`, `update_binding`, `enqueue_action`), a hash naming no object row resolving to 0, which the foreign key refuses, so a dangling name still fails the write as it did; a lookup by hash seeks `objects_by_hash`; a read answers the hash, read off the object row by the id. Guard: invariants "objects: a write naming a body no object row holds is refused, by its hash or its conflict's", "objects: a body named by its hash is written as its id and read back as its hash" and "enqueue: several actions in one transaction, one refused (a body no row names)"; that every read answers the hash rather than the id is guarded by the 18 existing expectations that read a hash back (load, get, row, retained, purge, placements, conflicts, the queue's, the derivation pages and others), all failing when the reads answer the id, and by the generator's oracle tests.
- **Hot plans read the integer** (STORAGE §4.3): a write and a lookup by hash seek `objects_by_hash` once per name, then the pointer index by id; a page answers a body's hash by the object's rowid; the recount reads the six pointer indexes and never the name. Guard: invariants "objects: a write and a lookup by hash seek objects_by_hash, then the pointer index by id" and "objects: a read answers a body's hash by its id, and the recount joins ids alone".
- **The collector and erasure** (STORAGE §5, §11.5): unchanged rules on the new keys. Guard: every existing collector, release and purge scenario, and the erase scenario, whose purged mail now holds a body collected through `release_pins` and `delete_garbage_objects`: its name must leave pimdir.db (the object row and `objects_by_hash`) and index.db, and stays in both without `secure_delete`.
- **The index keys a body by `object.id`** (SEARCH §3, new paragraph, §4; migrations/search/0001_init.sql): `object.id` is `AUTOINCREMENT`, so an id a pass has not cleared names no other body; `placement.hash` becomes `placement.object`, the body's `object.id`, `CHECK (object > 0)`, no foreign key (a pass may delete a collected body's row before it moves a placement off it, as `placement.hash` had none); `placement_by_hash` becomes `placement_by_object`, partial on the pointer being set; `object_not_ok` is on `(status)` alone. `match_objects` joins a match's rowid to `placement_by_object` with no `object` row read; `categorised` joins `object_category` to placements directly; `attached`, `holding`, `coverage`, `coverage_all` and `object_placed` join by id; `upsert_placement` takes the hash and writes the id, a hash the index does not hold refused; `placements_gone`, `load_changed_items`, `load_missing_items` and `hit` answer the hash. Guard: invariants "index: a placement holds its body's object.id, a hash the index does not hold is refused, and an id is never drawn twice", "index: a body's placements are sought by its id, a text term's matches joining no object row", and the coverage plan expectation, now naming `placement_by_object (object=?)`.

Vectors: none moves. They name bodies by label resolved to the hash, which stays the observable; no expected answer changed and vectors/manifest.json is as it was.

Signatures: none changed. Every statement keeps its parameters, slots and answered columns, the hash where it was (checks/signatures.py passes on the unchanged queries/signatures.json), which is also why the generator builds and its 82 tests pass untouched. checks/names.sh now lists `object_hash` among the result columns, a name statements take and answer that no table holds any more.

## Proof that each check fails without its rule

Each rule was disabled in a scratch copy of migrations/, queries/ and checks/ under /tmp/claude-1000/, never through git, and checks/invariants.sh run there:

- `objects.id` without AUTOINCREMENT: "an id is drawn above every id drawn before" answers `1 2` for `3 4`, and the rehearsal's next object id fails after each of its three migrations;
- `queue.object` without its typeof CHECK: "every pointer at a body is a foreign key onto objects.id" fails;
- `bindings.shared_object` a foreign key onto `objects(hash)`: the harness fails at its first write naming a body (a foreign key mismatch);
- `insert_item` resolving a hash by a bare subquery, no 0: "a write naming a body no object row holds is refused" answers `0011|2`, the dangling write landing as a bodiless row;
- `list_object_placements` seeking `+hash`: the lookup plan expectation answers `211`;
- `list_mail_page_desc` reading the hash back through the name: the read plan expectation answers `006`;
- the index's `object.id` without AUTOINCREMENT: the index expectation answers `1|1|1|0`, the placement left on a deleted body naming the next one;
- `placement.object` without its CHECK: the unknown hash lands (`1|0|2|1`), and so does `../x`;
- `placement_by_object` keyed otherwise: the index plan expectation answers `0000`, and the coverage plan fails;
- `match_objects` joining through `object`: the index plan expectation counts an `object` read.

## Chosen here, for the owner

- **The hash stays the public name of a body in every statement.** Parameters and answered columns are unchanged, the statements resolving a hash to its id (a seek on `objects_by_hash`, a page the write just dirtied) and back (a rowid seek). Taking ids would have saved those seeks but changed the signature of some fifty statements, and every caller would have to carry ids it never shows.
- **A hash naming no row is refused, never written as no body.** A bare subquery would write NULL for an unknown hash; the statements write 0 instead, which the store's foreign key and the index's CHECK refuse, so the store keeps the refusal its foreign key onto `objects(hash)` gave.
- **AUTOINCREMENT on both keys**, as `items.id` has, rather than a plain rowid that reuses the highest id once its row is deleted: one `sqlite_sequence` row per transaction, and no pointer the collector or a pass outlived names another body.
- **The index keeps its own `object.id`**, joined to the store's object by hash (`objects_gone`), never by the store's id: index.db stays derived, rebuilt by hash from any store.
- **No foreign key on `placement.object`**, as `placement.hash` had none; `CHECK (object > 0)` in its place.
- **Column names**: `items.object` and `queue.object` (an integer named `_hash` would mislead); the binding columns keep their names, which already said `object`.

## io-pimdir follows

The schema and statements it vendors from spec/ load unchanged in signature; its own SQL does not: src/sql.rs (`LIVE_BYTES`, the recount and the two `DANGLING_*_OBJECTS` diagnoses read `object_hash` and the queue's), src/sql/search.rs `MESSAGE_HASH` (`p.hash`), src/client/search/compile.rs (its planner's joins `placement p ON p.hash = o.hash`, to join `p.object = object_text.rowid`), and the raw SQL of its tests (tests/refcount_property.rs, tests/store_text.rs, tests/generated/replay.rs, tests/search.rs and the others naming `object_hash` or `placement.hash`). The Android app's own index statements (rust/pimdir/queries/index/card_facts.sql, card_categories.sql, agenda_occurrences.sql) and rust/src/search/compile.rs name `p.hash` and `i.object_hash` likewise. checks/io-pimdir.rev moves with the io-pimdir commit that passes.
