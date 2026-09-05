---
cairn: log
change: change-feed-cursor-and-stamps
date: 2026-09-05
---

# The change feed misses nothing: the cursor is the last stamp drawn, every stamp is unique, a rename restamps

Three consumers of the feed lost rows, verified with the canonical statements on the canonical schema. The cursor recorded `next_change` and the reads asked for `changed > :since`, so the first row stamped after every pass was never folded. `stamp_item` drew the counter without bumping it and neither STORAGE §4.5 nor GUIDE §5 named `bump_next_change`, so two rows could share a stamp and a page cut between them skipped the second. A rename stamped the collection and no item, so the indexer dropped the old placements through `placements_gone` and never learned the new id: the whole collection left the index.

`load_change_cursor` now answers `next_change - 1`, the last stamp drawn, and a consumer reads above it. `stamp_item` sets `changed` to `-1` and the new `items_stamp_request` trigger draws and bumps, so no writer reads the counter and `bump_next_change` is gone. `collections_restamp_items` requests a stamp for every item of a renamed collection under its new id. `objects_count_collect` counts a collected object in `store_meta.purges`, so the index runs `objects_gone` after a collection and not only after a purge. STORAGE §4.5 and §13, SEARCH §4, GUIDE §14 and §15, OVERVIEW §9. Guarded by checks/invariants.sh.
