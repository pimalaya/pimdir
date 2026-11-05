---
cairn: tasks
change: storage-draft-09
---

# Tasks

Each step leaves `nix flake check path:$PWD` green before the next.

## pimdir

- [x] migrations/storage/0001_init.sql: `items.id`, children keyed by `item`, `bindings (item, collection)` onto `items(id, collection)`, `marks` and `base_marks` with their CHECKs, the stamp trigger on `marks`, `items_by_sort` covering `marks`, `items_unread`, `bindings_by_link` dropped
- [x] queries/storage: the 120 statements reaching a child, through the item's id; `:marks` and `:base_marks` on the four row writes; the `flags` slot holding the other flags; the reads' flag tests on the bits
- [x] queries/storage: `list_owing_bindings`, `list_lacking_items`, `link_senders_of_by_link`
- [x] queries/search: the statements reading the store's children (load_changed_items, load_missing_items, hit, items_to_reexpand)
- [x] checks/invariants.sh: the harness binding `:marks` from a set, the direct table writes on the new keys, scenarios for the bits (a `\seen` row beside a `\Seen` bit), the owing statements against every status, the per-page sender rule
- [x] checks/schema.sh, names.sh, floor.sh, vectors.py (the summary columns less `item`), waivers
- [x] vectors/sync: no case added, the existing cases pin every push a delta owes; the owing statements pinned per status by checks/invariants.sh
- [x] STORAGE.md §4.3, §4.4, §4.5, §9.3, §13, §14, §14.2; SYNC.md §10; SEARCH.md Status; GUIDE.md; OVERVIEW.md if a concept moves; README
- [x] Versions bumped; log entry (cairn/log/2026-11-05-storage-draft-09.md)
- [ ] Tags storage-draft-09, sync-draft-08 and search-draft-09, the user's to make

## Followers

- [ ] io-pimdir: re-vendor, `:marks` in the write path, loads by the owing statements, the suite over the new spec; pimdir CI pins it
- [ ] android: the shape's forks and PimdirStorage; the phone run of performance-audit-2026-11-05
- [ ] neverest, himalaya, cardamum, calendula pinned to that io-pimdir
