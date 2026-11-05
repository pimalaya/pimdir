---
cairn: tasks
change: performance-audit-2026-11-05
---

# Tasks

The ledger of proposal.md: one line per action, each closed by the log entry, vector or check that answers it. Measurements are desktop unless stated; bench/ reproduces them from the repository root: `nix-shell -p python3 --run 'python3 -I cairn/changes/performance-audit-2026-11-05/bench/write_bench.py migrations/storage/0001_init.sql DIR 20000'`, then query_bench.py with `migrations/storage/0001_init.sql migrations/search/0001_init.sql DIR 100000 1` (it builds the store it reads); marks.sql runs on a copy of that store, occ.sql on an empty file, each through `sqlite3` and the floor's shell (flake.nix, `sqliteFloor`).

## Phase 0, measure

- [ ] pimdir: tag storage-draft-08, sync-draft-07 and search-draft-08 at the commit pinning io-pimdir 42a2f26 (the user's)
- [x] pimdir: bench/draft09.c, draft-09's candidate store schemas against draft-08 on 3.50 and the 3.18 floor (proposal.md, The draft-09 bench): flags as columns and the integer placement id kept, the pending stamp dropped
- [x] android: the app's write path against the chosen schema on the host (Draft09Measure, 2026-11-05): −45% a page in statements, 28 to 16 runs a message; draft-09's content settled (proposal.md, The draft-09 bench)
- [ ] android: the phone run, once the app opens draft-09 stores

- [x] android: a page write split on the host and the phone (a-page-lands-in-few-statements, 2026-11-05): 97% and 86% inside statements; the cause, `create_param` through `execSQL` flushing the statement cache, fixed there (F4)
- [ ] android: the phone's profile after the list-binding fix, ranking what is left (a-page-lands-in-few-statements' open task; F4, phase 1 item 9)
- [ ] android: a test failing a page write whose profile names a DDL statement run through `execSQL` (F4)
- [x] io-pimdir: tests/search_scale.rs before and after `prepare_cached`: 50,000 messages written through the owner in 17.55 s, then 2.94 s; the index in 5.05 s, then 4.80 s (F4)
- [x] pimdir: the keyset reads planned on the floor, a param table with `value` untyped (checks/floor.sh, cairn/log/2026-11-05-the-floor-plans-the-keyset-reads.md); STORAGE §4.4's sentence on the column's affinity waits for storage-draft-09 (F10)

## Phase 1, implementations and the index

- [x] io-pimdir: `prepare_cached` throughout, rusqlite's `cache` feature on, 256 statements per connection (io-pimdir cairn/log/2026-11-05-statements-are-prepared-once.md) (F4)
- [ ] pimdir: `list_owing_bindings` and `list_lacking_items` (STORAGE §14, SYNC §10), a sync vector on every status, plan asserts (F3)
- [ ] io-pimdir: delta and last-page loads by them, closing a-delta-loads-what-it-names (F3)
- [ ] io-pimdir: the planner in src/search/plan.rs: scope, term sets read once, a store-order or smallest-set driver, dedup by `(account, seq)`, a keyset cursor, a count apart (F1, F11)
- [ ] pimdir: SEARCH §8.2, a hit placed by its first placement walked, the store-order form by membership in each term's matches; vectors walking pages to the end (F1)
- [ ] android: the bridge on the planner and its compile.rs fork removed; a page from one statement on the index handle; no unpaged hits across JNI (F1, F11)
- [ ] android: lists bound inline per arity, reads on a reader connection (F9)
- [ ] pimdir: the index without `flag`, `flag:`, `tag:` and `is:` read from the store; summary text rewritten only when it changed (SEARCH §3, §4, migrations/search) (F6)
- [ ] pimdir: occurrences bounded by the longest span (SEARCH §7, occurrences_between, occurring_between, a multi-day vector) (F7)
- [ ] io-pimdir, android: coverage once per query, kept per collection until its stamp moves (F8)
- [ ] android, ranked by the phone's profile: an item inserted with its flags known (no `SET_FLAGS_KNOWN` after `INSERT_ITEM`), the sender rule once per page, one lookup by link for unheld members, multi-row inserts of a page's fresh members (F4)
- [ ] android: the index refreshed when a fill pauses, the list recounted at most once per pass while chunks land in parallel (F2, F12, F13)
- [ ] android: the sender and subject `LIKE` tested on the rows above the index cursor alone (F12)
- [ ] io-pimdir, android: snippets for the rows shown, the extraction kept per hash for the page (F12)

## Phase 2, the store schema before storage-v1

- [ ] Decide: item 10 now, item 11 now or in v2 (proposal.md, Decisions)
- [ ] pimdir: the system flags as columns, `items.marks` and `bindings.base_marks`, as the representation (or the mirror and its invariant), their indexes, the counts and seen tests on them, vectors pinning the exact-bytes split (F2, F4)
- [ ] pimdir: the integer placement id, every child keyed by it, the index keyed on it (F5, F6)
- [ ] pimdir: the stamps, a-page-lands-in-few-statements' step 2 only if the flags stay rows (F4, proposal.md Decisions)

## Phase 3, only if measured necessary

- [ ] A stored owed marker for deltas over a million members (F3)
- [ ] A bounded purge log for the index's reconciliation (F12)
- [ ] Per-collection counters for the unread badges (F2)
- [ ] Contentless FTS4 with a dead-rowid list on Android, an erase rebuilding it (F12)
