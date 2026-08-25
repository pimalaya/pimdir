---
cairn: tasks
change: refcount-floor
---

# Tasks

## Landed in this repository

- [x] `CHECK (refcount >= 0)` on `objects` in migrations/0001_init.sql.
- [x] SPEC.md §7 (the floor, and why it is not merely tidiness) and the §13 encoding note for `refcount`.
- [x] SPEC.md §6: the draft reconciliation states the table rebuild, since `ADD COLUMN` cannot reach a constraint.
- [x] SPEC.md §5 and the `list_garbage_objects` comment: the `<= 0` sweep predicate keeps a live justification (the read-only reader) instead of the stale one.
- [x] Log entry.

## Left to io-pimdir

Its own change, with its own log entry and a CHANGELOG line under `### Fixed`.

- [ ] The constraint in io-pimdir's inlined copy of the schema.
- [ ] `reconcile_draft_shape`: rebuild `objects` (create constrained, copy, drop, rename) when `sqlite_schema` shows the constraint absent, inside the existing transaction, after any column and index reconciliation, recreating `objects_garbage` and running `PRAGMA foreign_key_check` before the commit.
- [ ] Recompute refcounts before constraining, so a store carrying real drift migrates rather than failing to open.
- [ ] Tests: a store written without the constraint gains it on open and keeps its rows; a store with a negative count is repaired then constrained; a double release now fails loudly rather than passing.
