---
cairn: tasks
change: retained-page-by-seq
---

# Tasks

## Landed in this repository

- [x] `items_retained` becomes `(collection, seq)` in migrations/0001_init.sql, with the comment saying which reads it serves.
- [x] `list_retained_page` pages on `seq` in queries/items.sql.
- [x] SPEC.md §14.1: the `:after` contract for the retained page, and why it differs from `list_items_page`.
- [x] Measure every retained read against both index orders; reject the audit's proposed `(retained_at)` index on the measurement.
- [x] Log entry.

## Left to io-pimdir

- [ ] The inlined index and statement, and the `--after` type on the retained listing.

