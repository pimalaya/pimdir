---
cairn: log
change: refcount-floor
date: 2026-08-25
---

# The refcount cannot go negative unnoticed

`objects.refcount` was a plain `INTEGER NOT NULL DEFAULT 0` maintained only as `refcount + :delta`. It now carries `CHECK (refcount >= 0)` in the canonical schema, and the format says what the reconciliation of an existing store must do to reach it.

## Why the floor, and not just the sweep

The change was proposed on the grounds that a negative count "stays invisible". Reading the schema, that is half the story, and the other half is worse. All four pointer columns carry a foreign key onto `objects(hash)`, so a negative count has exactly two futures, neither of which names the release that caused it. Both were reproduced against the canonical schema:

| the body | stored count | what happens |
| --- | --- | --- |
| still pointed at by a live item | `-1` | `DELETE FROM objects WHERE refcount <= 0` is refused: `FOREIGN KEY constraint failed` |
| pointed at by nothing | `-1` | swept, one row gone, no error, no trace |

The first is the one worth the constraint. The failure surfaces in the garbage sweep, a statement that names neither the object nor the miscount, inside the write transaction, so the write fails and every subsequent write fails the same way. The store is wedged and says only `FOREIGN KEY constraint failed`. The second is the invisible case the proposal named.

The constraint moves the failure to the statement that caused it, which reports `CHECK constraint failed: refcount >= 0` at the release rather than at some later sweep.

## Checked per statement, never deferred

Confirmed against SQLite: the check fires on the offending `UPDATE`, not at `COMMIT`. A transaction therefore cannot net a dip below zero back out, and that is the right behaviour rather than a limitation. A correct batch never dips, because it releases no more pointers than the hash holds; one that does was already wrong before the constraint reported it. `recompute_refcounts` cannot dip by construction, since it assigns a `count(...)`.

## What the reconciliation must do

SQLite has no `ALTER TABLE … ADD CONSTRAINT`, so §6's draft reconciliation could not reach this with the `ADD COLUMN` it already allowed. §6 now states the rebuild, and states four rules with it, each one verified rather than assumed:

- **Repair before constraining.** Rows are checked as they are copied, so an unrepaired store fails the rebuild and does not open. `recompute_refcounts` is the repair, and it can only write counts at or above zero, so it always terminates. Verified on a store carrying `-2`, `1` and `5` against true counts of `2`, `1` and `0`: rebuilding first fails on the copy, repairing first migrates every row.
- **`PRAGMA foreign_keys` off for the rebuild.** `DROP TABLE objects` is otherwise refused by every key referencing it. `PRAGMA foreign_key_check` before the commit is what replaces the enforcement given up, and reported no violation on the rebuilt store.
- **Recreate the indexes.** They belong to the dropped table and go with it; `objects_garbage` has to be created again. This one raises no error at all, it only leaves a store that silently scans.
- **Detect the constraint from `sqlite_schema`.** `PRAGMA table_info` reports name, type, nullability and default, and never says whether a column is constrained. Confirmed: the pragma output is identical either way.

After the rebuild the foreign keys still bind to the new table, so nothing has to be re-pointed by hand.

## Also corrected

§5's garbage-collection bullet justified the `<= 0` sweep predicate as the thing that keeps a negative count from "leaking for good with nothing reporting it". Under the floor that reading is stale, and the predicate would now read as dead width. It has a live reason instead, and it is the reader: a reader opens read-only (§8), so it cannot apply the floor to a store written before the constraint existed, and a negative count there must still read as collectable rather than as live. The same correction went into the comment on `list_garbage_objects`.

§13 had no `refcount` entry at all, which for a column two sections make claims about was a gap. It has one, saying what the count counts, that the floor is normative rather than defensive, and that `0` is a real value rather than a sentinel.

## Not landed here

io-pimdir's `reconcile_draft_shape` has to grow the rebuild, and its inlined schema the constraint. That is its entry to write.
