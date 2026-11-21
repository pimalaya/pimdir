---
cairn: log
change: an-item-keeps-local-state
landed: 2026-11-21
---

# An item keeps local state

storage-draft-15 and search-draft-16, neither tagged, so both are edited in place and no number moves (sync-draft-15 likewise, for the one sentence it gains). cairn/changes/an-item-keeps-local-state is the proposal (why: cairn/changes/compared-with-notmuch, Part 1); this lands its spec side, owner decisions of 2026-11-21 included (bounds; labels kept as written, matched folded, a folded duplicate a no-op on add). io-pimdir follows.

## Rules and the check guarding each

- **The table** (STORAGE §4.3, §13, migrations/storage/0001_init.sql): `item_property(seq, key, value)`, `WITHOUT ROWID`, the three columns its key, `item_property_by_value` on `(key, value)`. Guard: checks/invariants.sh "An item keeps local state" (every expectation below), its plan expectation naming `item_property_by_value` and the table's key, the rowid expectation of "Small rows carry no rowid", and checks/rehearsal/populate.sql, which now fills the table so the rehearsed migrations prove they keep its rows.
- **Bounds held by the schema**: a key `<namespace>/<name>` of `[a-z0-9._-]`, at most 64 bytes (CHECK); a value 1 to 1,024 bytes of UTF-8 with no NUL (CHECK); at most 64 values per key and item (`item_property_bounded`, a value already held passing); a seq some row of `items` holds (`item_property_needs_item`). Guard: four invariants expectations, refused and accepted values at each bound.
- **Life with the seq** (§4.3, §9.1, §11.2, §11.5, §12, §14.3): kept by a retention, a restore and a rekey, kept by a purge leaving another row of the seq, gone with the last row (`items_drop_properties`), a collection's delete included; erasure scrubs it. Guard: the invariants expectations "a retained row keeps", "a purge leaving another row", "a restore", "a rekey", "the purge of the last row", "a collection's delete", and the erase scenario, whose purged mail now holds a property whose word must leave pimdir.db.
- **The stamp** (§4.5): a value added or removed stamps every row holding the seq, a no-op none (`item_property_stamp_insert`, `item_property_stamp_delete`). Guard: the invariants stamp expectations, and vectors/search/refresh.json's new case "an item keeps local state", whose feed checks/vectors.py re-derives.
- **Eviction keeps an item holding a property** (§11.3, `evict_before`): no relisting restores local state, a widening naming the member under a new seq. Guard: the invariants eviction expectation.
- **Never read by sync, never pushed** (§4.3, SYNC.md §2 and §3): Guard: checks/names.sh's new check that no statement of the load and the write STORAGE §14 opens with, nor one SYNC.md names, reads `item_property`, and the invariants expectation that `list_owing_bindings`, `list_lacking_items` and `load_items` answer the same before and after a property lands. No sync vector: a vector's store states no property and its runs stage none, so a vector could only restate that nothing happens; the sync format would need a `SetProperty` mutation SYNC.md must not define.
- **The `set-property` action** (§15.2, §15.3, §15.4, §15.6, payloads/set-property.v1.schema.json): one key, `add` and `remove` (one or both), removes then adds in order, a label compared folded, applied as no source and needing no capability, parked when no live row of its collection holds the seq or past 64 values; `pimdir/` keys other than `pimdir/label` malformed by the schema; a value's 1,024 bytes the text's rule, as `v`'s is. Readers' overlay folds it. Guard: 27 cases of vectors/payloads.json, checks/vectors.py's outcome (schema plus the byte rule) and its new require that two cases are malformed by the text alone (a lone surrogate, which the text refuses too, has no case: strict JSON parsers, serde_json among them, refuse the whole file holding one);
 the shape the prose writes, compared with the schema (the shape notation gains `( a / b )`, one or both, read as the schema's `anyOf`); the invariants scenario enqueuing, claiming and applying one with its receipt.
- **Readers** (§14.1): `list_item_properties`, `list_property_values` (a loose index scan, one seek per value), `list_property_holders`, `list_value_holders`; the owner's `add_property` and `remove_property`. Guard: the invariants scenario runs each, checks/names.sh, queries/signatures.json restated.
- **`label:` and `property:`** (SEARCH §8 table, §8.2, §8.3 ABNF and Values, §8.4, §10, §11): read from the store (`list_property_values` then `list_value_holders`), never from the index; a label folded both sides as Annex A.2 folds `fn`, a property byte for byte; an empty value, one past 1,024 bytes or holding U+0000, a `property:` value without `=` or whose key no `property-key` reads, refused `invalid-value`; the reserved forms and the wildcard rule apply as to every non-text field. Guard: 31 cases of vectors/search/queries.json over 8 properties of vectors/search/store.json, checks/vectors.py re-deriving every refusal and the hits of every one-term `label:` or `property:` case (16 in queries.json, 10 queries of the refresh case).

store.json moves to `v` 3 (its `properties`), refresh.json to `v` 3 (a store's `properties`, the `property` write). No existing case's hits move: the properties sit on existing items and no existing query reads them; the store gains no item.

## Proof that each check fails without its rule

Each rule was disabled in a scratch copy of the tree under /tmp/claude-1000/, never through git, and the check guarding it run there; each failed, naming the rule:

- the key CHECK dropped: invariants, "the schema refuses a key past its bounds" (every key taken);
- the value CHECK dropped: invariants, "the schema refuses a value past its bounds";
- `item_property_bounded` raised to 6,400: invariants, the 65th value taken;
- `item_property_needs_item` disabled: invariants, a seq no row holds taken, and the orphan outliving a collection's delete;
- the stamp limited to one collection: invariants, "a value added stamps every row holding the seq";
- `items_drop_properties` disabled: invariants, the last purge and a collection's delete leaving them, and the erase scenario finding the property's word in pimdir.db;
- `items_drop_properties` firing on every delete: invariants, "a purge leaving another row of the seq keeps them" and the restore;
- a trigger dropping them with a binding: invariants, the rekey, the retention, the partial purge and the restore;
- `item_property_by_value` dropped: invariants, the plan expectation, and the index gate;
- `evict_before` without its property clause: invariants, the eviction expectation;
- `list_owing_bindings` reading `item_property`: invariants, "a property derives no push", and checks/names.sh's new check;
- checks/vectors.py comparing a label byte for byte: six queries.json cases and the refresh case; its add no-op compared byte for byte: refresh step 2's feed and hits; its byte rule dropped: the two payload cases malformed by the text; the schema's `pimdir/` reservation dropped: the shape comparison and the two reserved-key cases; its `property:` value check dropped: six refusal cases; the stamp limited to the named row: refresh steps 1 and 3.


## Chosen here, for the owner

- The `pimdir/` reservation is held by the payload schema (a key under `pimdir/` other than `pimdir/label` is malformed) and by the owner rule, not by a CHECK: a later version defining `pimdir/session-key` then needs no schema edit and raises no `read_version`.
- A value is never empty and never holds NUL (CHECK and schema); a `label:` or `property:` query value past the bounds is refused `invalid-value` rather than answered empty.
- `set-property` names one key; `add` and `remove` are each optional but one must be stated, each 1 to 64 distinct values; removes apply before adds, so a value both name is held after (a respelling), not malformed.
- Under `pimdir/label` a remove is folded too: it removes the held spelling whose fold is its own.
- A `set-property` parks unless a live row of its row's collection holds the seq: a tombstone's or a retained row's properties are kept, never changed through the queue.
- An eviction keeps an item whose seq holds a property, as it keeps one a person's reference names.
- `list_property_holders(key)` and `list_value_holders(key, value)` are two statements rather than one taking a nullable value, which would read the key's whole range for a value.
- A label matched folded is found by `list_property_values` (the spellings held) then `list_value_holders` per spelling whose fold matches, since SQLite folds no Unicode and the table keeps three columns; a folded column would make this one seek.
- The overlay folds a pending `set-property` queued on the collection it shows; one queued on another collection holding the same seq shows once applied.

## Left

- io-pimdir: the table, the four reads and two writes, the `set-property` apply and overlay, `label:` and `property:` in its query compiler, the new payload, query and refresh cases. checks/io-pimdir.rev moves with the io-pimdir commit that follows; until then checks/implementation.sh is expected to fail on the new cases.
- The generator (generator/) writes no property yet: its oracle states, for the four new reads, the empty answers of a store holding none (generator/src/oracle.rs, `properties`), since its test requires an expectation for every read statement.

