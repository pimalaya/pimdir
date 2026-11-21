---
cairn: tasks
change: the-owing-rows-are-marked
---

# Tasks

## 1. The standard

- [x] `bindings.owes`, `items.lacks`, the views `binding_owes` and `item_lacks`, fifteen recompute triggers, two flag-row guards and the partial indexes `bindings_owing` and `items_lacking` in migrations/storage/0001_init.sql, storage-draft-15 edited in place
- [x] `list_owing_bindings` and `list_lacking_items` seek the marks, the second walking the collection only for a source no row of `sources` names; signatures unchanged
- [x] STORAGE.md §4.6 (new), §4.3 and §14; SYNC.md §10; GUIDE.md
- [x] checks/invariants.sh: the probe after every statement of every scenario (each mark equals its rule and covers what the statements before the marks answered), the scenario "The owing marks follow every write", the plan checks moved to the marks; each of the seventeen triggers, the view's keyword term, the walk and the statement's mark shown necessary by a mutation run (log)
- [x] Log entry cairn/log/2026-11-21-the-owing-rows-are-marked.md

## 2. Implementations

- [x] io-pimdir: spec re-vendored, suite passing, the no-op sync and the import measured on the 517k tier (log)
- [ ] io-pimdir: spec/REVISION and checks/io-pimdir.rev once the owner commits both sides
- [ ] The Android app: its own statements against the store (see the log's "Implementations follow")
- [ ] Existing storage-draft-15 stores carry neither column: io-pimdir refuses them as damaged (the schema text differs), an implementation not comparing the schema meets "no such column" at its first delta; each is rebuilt by a fresh sync, as the owner decided for drafts
