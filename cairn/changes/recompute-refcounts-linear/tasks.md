---
cairn: tasks
change: recompute-refcounts-linear
---

# Tasks

## Landed in this repository

- [x] Rewrite `recompute_refcounts` in queries/objects.sql as `UNION ALL` of the four pointer columns, `GROUP BY hash`, left-joined against `objects`.
- [x] Verify the plan with `EXPLAIN QUERY PLAN` against a populated store; record the before and after in the log entry.
- [x] Correct the complexity claim in §7 and §14.
- [x] Log entry; SPEC and queries updated together.

## Left to io-pimdir

Its own change, with its own log entry there. The format is what binds, and it now states the linear form; io-pimdir keeps `ADJUST_REFCOUNT` on the write path (a §4.4 substitution it already records) and gains the recompute as its repair.

- [ ] io-pimdir: inline it, drop it from the `SUBSTITUTED` list in `tests/spec_drift.rs`, and use it for `check --fix`'s repair.
- [ ] Test: a seeded drift is repaired to the exact pointer count, including an object pinned twice by one item (body and conflict body) and one pinned by a queue row.
