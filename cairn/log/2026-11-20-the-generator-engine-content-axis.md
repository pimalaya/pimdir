---
cairn: log
change: the-freeze-plan
landed: 2026-11-20
---

# The generator's engine, second part: the content axis

The second part of plan 2's "The scripted remote states", of cairn/changes/the-freeze-plan. No part of the standard moves.

- **A DAV remote** (generator/src/remote.rs): resource names as handles, an ETag per resource as its revision, its sync token as the checkpoint, every page carrying the bodies a multiget read (SYNC §4), edits and removals by another client, an accepted `Update` or `Add` answering the revision the resource holds.
- **The content axis** (generator/src/engine.rs, SYNC §5): a member carrying its body names its item at `Full`, base and revision set; a revision the base does not hold over no local edit is pulled, body, summary, addresses and sort key restated, reported `ContentChanged`; a local body off the base pushes an `Update` gated on the base revision, rebased on the revision answered; both record the binding conflicted under `Manual` with the observed revision and the carried body, the item keeping its own, reported `Conflicted`, pushing nothing; a tombstone's `Remove` gated on the base revision.
- **A person's resolution** (generator/src/queue.rs, STORAGE §15.3, SYNC §7): an `update` stating `resolves` naming every conflict it meets settles it, the base adopting the conflict's revision and body; one naming none of a conflict it meets, or stating `resolves` and meeting none, parks. An edit moves its binding's `shared_object` onto its body (GUIDE §12 step 4), a reading listed in generator/README.md.
- **A history** over one address book: a first round, a server edit pulled and a local one pushed, an edit on both sides in conflict, a resolution pushed on the resolved revision, a delete each way, a run with nothing left to do.
- **Checks**: every push of vectors/sync, `Update`s and gated `Remove`s now among the typed ones, carries the key this crate derives; each step's store is written and self-checked; tests state each run's outcome from SYNC. Broken by hand to see each fail: a both-sides edit pulled rather than conflicted, a resolution keeping the old base, an accepted `Update` not rebased, a pull keeping the old sort key (which passed until a test stated it).
