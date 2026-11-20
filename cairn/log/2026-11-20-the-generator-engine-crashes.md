---
cairn: log
change: the-freeze-plan
landed: 2026-11-20
---

# The generator's engine, ninth part: crashes

The ninth part of plan 2's "The scripted remote states", of cairn/changes/the-freeze-plan. No part of the standard moves.

- **An interrupted round** (generator/src/engine.rs, remote.rs, SYNC §5, vectors 34 and 35): a remote cut after a number of pages fails the run there. What landed stays: the members named and stamped with the round's id, the round open with the cursor of its last page landed and the latest checkpoint a page carried, no absence inferred, nothing pushed. The next run under the same scope resumes the round under its id from that cursor (`Remote::round_from`), its absences counting every stamp of the round, the earlier attempt's included, and closes it with the checkpoint landed before the cut. The open round's cursor is written by `set_round_cursor` and stated for `load_round`.
- **A push whose record was lost** (SYNC §4, §5, §6): a remote cut after a push it took fails the run before the write recording the outcome, so the store is left as it was. An `add` is then landed by the next listing naming its member, never pushed twice; a flag change never sent is pushed then; an `update` the server took is met by the next listing at the pushed body. A listed body equal to the placement's own is no divergence, the base adopting it and its revision, a binding conflict clearing; one a listing does not carry is recorded in conflict, and the upgrade fetching it clears the conflict when it is the placement's own, else lands it as the diverging body.
- **Commits**: a run's page writes, round close and coverage now land before its pushes, as the write after the last chunk does, so a cut push leaves the round closed.
- **A history** of a mailbox whose first round is cut after one page and resumed, then a run cut after its add was taken, the next landing it and pushing the flags left; and two address books, one listing bodies and one not, where a run is cut after its edit was taken, the next run and an upgrade meeting the pushed body.
- **Checks**: tests state each rule above from SYNC; every step's store is written and self-checked. Broken by hand to see each fail: a resume from the first page, an interrupted round closing, a lost outcome written, an equal listed body conflicting, an equal fetched body conflicting, the checkpoint landed before the cut lost.
