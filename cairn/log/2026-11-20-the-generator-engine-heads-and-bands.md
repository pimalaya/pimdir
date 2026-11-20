---
cairn: log
change: the-freeze-plan
landed: 2026-11-20
---

# The generator's engine, tenth part: heads, bands and refused cursors

The tenth part of plan 2's "The scripted remote states", of cairn/changes/the-freeze-plan, with the replay findings G11 and G17 of io-pimdir's generated suite. No part of the standard moves.

- **Delta heads** (generator/src/engine.rs, remote.rs, SYNC §4, §5): a run resuming an open round lists a delta head first where the connector lists them, from the round's checkpoint, or the source's for a band round. The head is merged as a page before the last: its members named and stamped with the round's id, its vanished handles dropped, its checkpoint recorded as the round's, no `Add` derived, no absence inferred. The round closes on the latest checkpoint a page or a head landed. `Run::head` holds it.
- **Band rounds** (SYNC §5, vectors 41 and 46): where the source's checkpoint is bound to no scope (`Remote::scope_bound`), a widening on one side lists only the band the coverage lacks, recorded as a band round (`open_round`'s `band`, stated for `load_round`): its pages carry no checkpoint and no undated member, its absences spare an undated member, and it closes widening the coverage to the scope asked. A band round is resumed only by a run that would list the same band.
- **A rejected cursor** (SYNC §4, §5, vector 36): a resume cursor the source rejects restarts the round over the same scope under a new id from its first page, the checkpoint the old attempt landed void, so the abandoned listing's stamps protect nothing.
- **A page handing no cursor** (SYNC §4, §5, vector 79): a page that is not the last and hands no cursor is refused before its write, and the run fails with the round open at the cursor landed before it.
- **G11**: a `Run` records what it was asked, as a sync vector's `run` does: its options (scope, `accept_absences`), the source's conflict policy, an upgrade's handles.
- **G17**: a member whose body equals the item's, another source having folded it first, reports no `ContentChanged`, which names a body the item took; the equal-body rule of the ninth part already settles it with no event, now held by a test. G16 (a join's `prefer-existing` debt) was settled by the format-11 part.
- **A history** of four mailboxes: a round cut and resumed after a head naming an arrival, a flag change and a stated removal; a round cut, a message lost unannounced and the cursor rejected; a page handing no cursor; a band over September cut and resumed after a head, an undated message lost unannounced kept.
- **Checks**: tests state each rule above from SYNC; every step's store is written and self-checked. Broken by hand to see each fail: no head listed, a restart keeping its id, a refused page written, no band listed, a band round dropping an undated member.
