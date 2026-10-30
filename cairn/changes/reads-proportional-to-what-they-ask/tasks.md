---
cairn: tasks
change: reads-proportional-to-what-they-ask
---

# Tasks

From the 2026-10-11 performance audit (p1p2-report #4, #5, #6 and §2.10 asserts 1 to 4), re-verified on 2026-10-18.

## Decisions (landed 2026-10-30)

- [x] Flag spelling: a flag set written as `json()` writes it, sorted by code point, each flag once; STORAGE §13 (decided 2026-10-30: no `seen` column)
- [x] #5 search: `LIKE` kept, no store-side FTS5, text search is SEARCH.md's index; STORAGE §14.1 (decided 2026-10-30)
- [x] Log entry

## Moved

- [x] #4 keyset bound, #6 counts and the seen test, search_mail under the bound and a page cap, plan asserts 1 to 4, GUIDE, followers: moved to keyset-reads-seek-their-bound (2026-10-30), statement text only
