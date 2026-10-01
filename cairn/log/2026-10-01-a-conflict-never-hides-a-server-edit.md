---
cairn: log
change: a-conflict-never-hides-a-server-edit
date: 2026-10-01
---

# A conflict never hides a server edit

io-pimdir's conflict property failed on CI (run 36866646724) with a source silently diverged from its server: two rules combined into a loss, each followed faithfully by the engine.

- **SYNC §5, content axis.** A `Conflict` placement carrying no `conflict_revision` (the item's conflict, §9) that meets a revision its base does not hold marks the binding conflicted with that revision and asks for the diverging body, whatever the source's policy, reported as `Conflicted`. The text was silent, read as "ignore it", and a delta lists the member once. Guarded by vectors/sync/33.
- **SYNC §7, `Remove` on a conflicted binding.** The base adopts `conflict_revision` and `conflict_object` together, as `Edit` does; an unfetched diverging body leaves `base_object` unknown. Keeping the old body made a base claim the remote held it at the new revision, so a revival by another source read in sync. Guarded by vectors/sync/32, whose expected `base_object` moves from `c1` to `null`.
- **SYNC §3, rule 4.** States that a base naming no body differs from every body, which the `Remove` rule relies on to project a revived item `Dirty`. The reference engine already read it so.

GUIDE.md's sync and mutate steps follow. Normative edits after the `draft-01` tag, so the three Status lines, the README and AGENTS §2 move to `draft-02`; the `draft-02` tag is the user's to make.
