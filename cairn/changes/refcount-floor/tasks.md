---
cairn: tasks
change: refcount-floor
---

# Tasks

- [ ] `CHECK (refcount >= 0)` on `objects` in migrations/0001_init.sql and in io-pimdir's inlined copy.
- [ ] io-pimdir `reconcile_draft_shape`: rebuild `objects` (create constrained, copy, drop, rename) when the constraint is absent, inside the existing transaction, after any column and index reconciliation.
- [ ] Recompute refcounts before constraining, so a store carrying real drift migrates rather than failing to open.
- [ ] Tests: a store written without the constraint gains it on open and keeps its rows; a store with a negative count is repaired then constrained; a double release now fails loudly rather than passing.
- [ ] SPEC.md §7 and the §13 encoding note for `refcount`.
- [ ] Log entry in both repos; io-pimdir CHANGELOG under `### Fixed`.
