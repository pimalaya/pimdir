---
cairn: tasks
change: search-milestones
---

# Tasks

Deferred to the 2027 NLnet plan, Task 2 "pimdir Notmuch".

## pimdir (this repository)

- [x] M0: the search part in draft, its schema, statements and first vectors (cairn/log/2026-09-03-search-part.md, 2026-09-05-search-roles-threads-horizon.md)
- [x] SEARCH §8: an ABNF for the query; precedence of `or` and the implicit `and`, `not`, phrases, `*`; an unknown field refused
- [x] SEARCH §8: the error shape of a refused query (position, expected, known fields) (cairn/log/2026-10-27-search-grammar-refusals-chunks.md)
- [x] The hit, coverage and error shapes as JSON Schema, with a snippet and an address per hit: published by io-pimdir (`pimdir-search`, `pimdir-count`, `pimdir-query-error`), the error object normative in SEARCH §8.4
- [x] SEARCH §6: extraction records chunk boundaries per object hash (shared with cairn/changes/embedding-index)
- [x] vectors/search: cases for `or`, `not`, parentheses, `*`, relative dates, `has:attachment`, `is:encrypted`, `changed:`, the `name` and `relevance` sorts, a threaded listing, a range outside the horizon, a refused unknown field
- [x] SEARCH §7 and migrations/search: `index_meta` records the time zone database version occurrences were expanded under; a new version re-expands (`items_to_reexpand`)
- [x] checks/vectors.py: validate the new cases' shape
- [x] GUIDE §15 and OVERVIEW §10 follow
- [ ] SEARCH.md leaves draft once io-pimdir answers every case

## Elsewhere

- [ ] io-pimdir M1 to M3: cairn/changes/search-feature
- [ ] M4: `tag`, `thread` (io-pimdir)
- [ ] Targets measured: index throughput on a 50k-mail store, query p95 at 1M items, against the 1.6 s `LIKE` baseline
- [ ] After Task 2: himalaya, cardamum, calendula and the GTK app on the library; the `LIKE` reads stay for consumers without the index
- [ ] ical: the database version exposed (cairn/changes/tzdb-pinned-and-versioned)
