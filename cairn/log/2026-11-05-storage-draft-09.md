---
cairn: log
change: storage-draft-09
date: 2026-11-05
---

# storage-draft-09: an integer placement id, the system flags as columns, deltas loading what owes a push

storage-draft-09, sync-draft-08 and search-draft-09 land as cairn/changes/storage-draft-09 proposes, every store recreated (STORAGE §4.2). The content was settled by measurement first (cairn/changes/performance-audit-2026-11-05, The draft-09 bench): on the canonical writer −53% SQL and −49% bytes a listed message, on the Android app's path −45% a page and 28 to 16 statement runs a message, unread counts 8 to 18 times faster.

Rules moved, and the check guarding each:

- **An integer placement id** (STORAGE §4.3, §13; migrations/storage/0001_init.sql): `items.id INTEGER PRIMARY KEY AUTOINCREMENT`, never shown, `(collection, link_id)` and `(id, collection)` unique; every child keyed by `item`; `bindings` keeps `collection`, held to its item's by a foreign key onto `items(id, collection)` that a rename cascades through; `bindings_by_link` dropped, `origin_for_link` and `destination_for_link` seeking `items_by_link` and the binding's key. Guarded by checks/schema.sh, checks/floor.sh (every write compiling on 3.18, an object's delete seeking its pointers) and the invariants scenarios on rename, cascade and refusal.
- **The system flags as bits** (STORAGE §4.3, §4.4, §4.5, §13): `items.marks` and `bindings.base_marks`, `\Seen` 1, `\Answered` 2, `\Flagged` 4, `\Draft` 8, `\Deleted` 16, each by its exact bytes, `0` to `31` and `0` for an unknown set by constraint; every other flag, `\seen` included, a row. `insert_item`, `update_item`, `insert_binding` and `update_binding` take the bits, the `flags` slot the other flags alone; reads join both into one text as before; `marks` is observable, so a system flag moving moves one stamp. `items_by_sort` covers `marks`, `items_unread` holds each collection's unread mail; counts, pages filtered on read state and `collect_before` test the bit. Guarded by checks/invariants.sh (a `\seen` row beside a `\Seen` bit, the stamp on a bit, the plans seeking no flag row) and checks/floor.sh (the keyset plans, covering or not).
- **A list parameter carries no affinity** (STORAGE §4.4): the sentence the floor check of 2026-11-05 waited for. Guarded by checks/floor.sh.
- **Deltas load what owes a push** (STORAGE §14, SYNC §10): `list_owing_bindings` names the handles whose placement may not be `Clean`, `list_lacking_items` the link ids of a source's `Created` projections; a delta loads those, what it lists or drops and its hints' links. A round's last page and a rekey keep `All`, since what each finds absent and whether a mass absence parks it are counted over every based binding in scope (SYNC §5, §8). Each statement names a superset, so a projection still decides every status. Guarded by the invariants scenario running both against every status (conflicted binding, conflicted item, tombstone, no base, a bit off its base, a row off its base, another object, a body the source lacks, and `Clean` named by neither); the existing sync vectors pin every push a delta owes, which io-pimdir's suite runs over the new loads. io-pimdir's `sync::tests::a_delta_loads_what_owes_a_push_never_the_collection` fails on a delta loading `All`.
- **The sender rule once per page** (STORAGE §14.2): `link_senders_of_by_link` over the `links` slot. Guarded by its invariants scenario and checks/names.sh.

Not in this draft: the pending stamp (nothing left to save once the flags are columns), the index's own changes (its `flag` table, the occurrence bound, the planner, a later search draft), bits for keywords.

All 257 statements run in checks/invariants.sh, none waived; `nix flake check path:$PWD` passes.
