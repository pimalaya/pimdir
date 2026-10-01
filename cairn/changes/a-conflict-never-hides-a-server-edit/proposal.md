---
cairn: change
id: a-conflict-never-hides-a-server-edit
status: landed
created: 2026-10-01
---

# A conflict never hides a server edit

> Cross-repo change, same id in two repositories, in this order: **pimdir** (here: the rule and vector 32) → **io-pimdir** (the engine, then a release). neverest picks the release up; the other readers of the format (pimalaya/android, himalaya-android-m3, linux, pimgate) are handled outside this set.

## Why

io-pimdir's `conflict_interleavings_are_reported_resolved_or_kept` property failed on CI on 2026-10-01 (run 36866646724, seed `b0c220b4…`): a source ends with its server holding a body the shared item does not, nothing conflicted and nothing reported. Two rules of this standard combine into the loss, and the engine follows both faithfully.

**1. An item conflict swallows a server edit (§5).** When two sources diverge under `manual` (§9), `items.conflicted` makes every binding project `Conflict` (§3), with no `conflict_revision` since the binding itself is not conflicted. §5 says what a `Conflict` placement does with a revision newer than its `conflict_revision`, and nothing about one that has none. The engine reads that silence as "the item's conflict is settled by an edit, never by this axis" and ignores the remote revision. Enumeration is incremental, so the changed member is listed once, dropped, and never listed again: the server edit is lost for good, with an empty report.

**2. A remove settles a conflict into a false base (§7).** On a conflicted binding, `Remove` adopts `conflict_revision` as `base_revision` but releases `conflict_object` and keeps the old `base_object`. The base then claims the remote holds, at the new revision, the body it held at the old one. While the tombstone stands nothing reads it; once another source's edit revives the item (§5, edit beats delete), the source projects against that false base, sees its server at the base revision, and never notices the server holds another body. Vector 32 freezes exactly this base (`base_revision: r2`, `base_object: c1`). `Edit` already adopts both halves together; `Remove` is the odd one out.

Minimal sequence (io-pimdir's conflict model, two sources s0 and s1, one item): s1 edits and syncs; s0 edits the stale copy, so the item diverges under `manual`; s1's server edits the item; s1 syncs (rule 1 drops the edit); later a remove settles s1's conflict (rule 2) and a server edit on s0 revives the item. s1 is left silently diverged.

## What

**§5, the content axis.** A `Conflict` placement whose binding carries no `conflict_revision` (the item's conflict, §9) and meets a revision its base does not hold MUST mark the binding conflicted, recording that revision and asking for the diverging body (§6), whatever the source's policy: the item's conflict is still open, so the source's own divergence is reported beside it rather than pulled into it. The two facts stay independent (§9 "A per-source conflict is its own fact"); an `Edit` settles both, a `Remove` settles both.

**§7, `Remove` on a conflicted binding.** The base adopts `conflict_revision` and `conflict_object` together, as `Edit` does. A diverging body not fetched yet leaves `base_object` unknown (`NULL`), never the old body: a base that does not know what its revision holds reads `Dirty` against any body (§3), so a revived item re-pushes the shared body gated on the revision, instead of reading in sync.

**Vectors.** Vector 32's expected binding moves to `base_object: null`. A new vector 33 covers rule 1: an item conflicted under `manual`, a delta listing the member at a revision past the base, the binding marked conflicted with that revision, `conflicts: 1` and a `Conflicted` event.

**Status.** Both are normative edits to SYNC after the `draft-01` tag, so SYNC's Status line, the README and the other two Status lines move to `draft-02` together, with the tag the user's to make (AGENTS.md §2). STORAGE was already edited after the tag (5d7f246) without a bump, so this bump covers both.

Not in scope: the cross-source axis itself (§9), the policies, STORAGE (no column changes; `base_object` is already nullable, §16).
