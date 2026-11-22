---
cairn: log
change: the-coverage-roll-seeks
landed: 2026-11-22
---

# The coverage roll seeks, storage-draft-16

A query no conjunct narrows rolls the temporal coverage up over every collection (SEARCH §8.2). io-pimdir read it with a statement of its own scanning every `sources` row, 0.57 ms on a store of 6,622 sources even in SQLite's own shell; a covering index on the three coverage columns gave nothing (56 pages against 121, the same time: the cost is the rows aggregated, not the pages). The owner decided on 2026-11-22 to answer it from the canonical schema.

## What moved

- migrations/storage/0001_init.sql: three partial indexes on `sources`, `sources_by_since` and `sources_by_until` holding the bounds of the sources that closed a round, `sources_filling` those that never closed one, empty at rest. STORAGE §3's rows and indexes paragraph names them.
- New statement `covered_all` (queries/search/covered_all.sql): the highest floor, the lowest ceiling and the sources never closing a round over every collection, each a scalar subquery the min/max optimisation answers from the end of its index. SEARCH §3's table names it and §8.2's temporal axis says a query no conjunct narrows may read it in place of rolling `list_coverage` up. On the 1M bench store it answers in 24 µs against 525 µs for the scan; io-pimdir's unscoped counts and pages lose 0.3 to 0.5 ms each.
- Storage moves to **storage-draft-16** (the indexes are schema, and io-pimdir 0.19 released stores of draft-15, which must be refused as an earlier engine's rather than as damaged): the Status lines of the three parts and conventions/gtd.md, README.md, AGENTS.md, GUIDE.md, STORAGE §4.2 and §17, `init_store_meta`. Sync and search keep their numbers, their Status lines requiring storage-draft-16.

## Checks

checks/invariants.sh: `covered_all` over a store no source syncs answers no bound and nothing filling; over four sources on three collections it answers what the aggregate over every row answers; its plan names the three indexes and never scans `sources` (fails without them, the plan reading the table). The draft scenarios name draft-16, and a draft-15 store is refused. queries/signatures.json restated; checks/names.sh, schema.sh, signatures.py and vectors.py pass.
