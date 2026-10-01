---
cairn: tasks
change: a-conflict-never-hides-a-server-edit
---

# Tasks

- [x] SYNC.md §5, content axis: add the rule for a `Conflict` placement with no `conflict_revision` meeting a revision its base does not hold (marks the binding conflicted, records the revision, wants the body, reported as `Conflicted`), next to the existing "newer than its `conflict_revision`" paragraph.
- [x] SYNC.md §7, `Remove` bullet: "the base adopts `conflict_revision` and `conflict_object` together, as `Edit` does; an unfetched diverging body leaves `base_object` unknown", replacing "its `conflict_object` is released".
- [x] SYNC.md §3: check that a base with a revision and a `NULL` object projects `Dirty` against a held body, and say so if the text leaves it open (rule 4 compares `object_hash` with `base_object`).
- [x] vectors/sync/32-remove-settles-a-conflict.json: expected binding `base_object: null`; update the note (the base no longer claims the old body at the new revision).
- [x] vectors/sync/33-an-item-conflict-reports-a-server-edit.json: new vector for the §5 rule (store: one item `conflicted: 1` under `manual`, two bindings, one whose server lists the member at `r2` past its base `r1` in a delta snapshot; expect the binding `conflicted: 1`, `conflict_revision: r2`, `conflict_object: null`, report `conflicts: 1`, event `Conflicted`). List it in SYNC §11 and vectors/README.md if they enumerate vectors.
- [x] Bump `draft-01` to `draft-02` in the three Status lines and the README; note in the log that the `draft-02` tag is the user's.
- [x] Log entry cairn/log/2026-MM-DD-a-conflict-never-hides-a-server-edit.md; status `landed`.
