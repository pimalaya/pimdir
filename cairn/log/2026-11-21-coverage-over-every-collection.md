---
cairn: log
change: coverage-over-every-collection
landed: 2026-11-21
---

# Coverage over every collection

search-draft-16, untagged, edited in place. A query no conjunct narrows asks coverage over every collection of the store; `coverage` binds them all to its slot and seeks `items_bodiless` once per collection, 3,311 times on the 517k Enron bench, about 8 ms of an answer that otherwise costs 4 (io-pimdir as-fast-as-notmuch, the planner tuning of 2026-11-21).

- New statement `coverage_all` (queries/search/coverage_all.sql): `coverage`'s four counts per kind over every collection, the slot unbound, walking `items_bodiless` once. SEARCH §3's table names it and §8.2 says a query no conjunct narrows may read it in place of `coverage`, which answers the same bound to every collection.

Checks: checks/invariants.sh, `coverage_all` answering what `coverage` answers bound to every collection's id, and its plan walking `items_bodiless` once with no slot, no per-collection seek and no scan of the store's items; checks/names.sh (SEARCH names it); queries/signatures.json restated. Run on a clean copy of the tree: the working tree holds an agent's stale worktree under .claude/, which the references check reads.
