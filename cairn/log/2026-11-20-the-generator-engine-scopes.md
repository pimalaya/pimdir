---
cairn: log
change: the-freeze-plan
landed: 2026-11-20
---

# The generator's engine, seventh part: scopes, narrowed and capped rounds, parked rounds

The seventh part of plan 2's "The scripted remote states", of cairn/changes/the-freeze-plan. No part of the standard moves.

- **The sync state** (generator/src/model.rs, writer.rs, oracle.rs, STORAGE §4.3): a source's state in a collection holds the last round id drawn, its coverage (the scope of its last closed round) and a round left open, with its scope and the checkpoint its pages landed. The writer replays them through `open_round`, `stamp_bindings`, `close_round` and `set_round_cursor`; the oracle states `list_coverage`, the coverage `list_collections` and `list_collections_by_account` answer (the latest floor, the earliest ceiling), and `load_round`.
- **Choosing the listing** (generator/src/engine.rs, SYNC §5): a run states its scope and whether it accepts absences. The open round is resumed under its id when it lists the scope asked for; a round opens when none closed, one is open over another scope, or the scope reaches outside the coverage; else a delta runs, recording a narrower scope as the coverage.
- **The scripted connector** (generator/src/remote.rs, SYNC §4): a round drops a dated member out of scope; a connector that narrows lists only members received from two days below the floor and says so, its last page handing every handle where it enumerates; a capped source lists its newest members alone and says so. A member a server loses unannounced is found by a round's absence alone.
- **Absences** (SYNC §5): a round finds absent the based bindings of its source in scope (an undated one is in scope) that it did not stamp; for a narrowed last page only those its enumeration lacks, none without one; none for a capped one. More than half of at least 20 in scope, or any after a listing naming nothing, park the round unless the run accepts absences: nothing is dropped, the round stays open with its checkpoint, and the run reports the absent and the bound counts. A create with no origin dated out of the run's scope waits, and no `Add` is derived while the round stays open.
- **A history** of five mailboxes: rounds over October, then September, then everything, a delta narrowing the coverage, a round over September dropping the absence in its scope alone while a create dated August waits, and one over everything pushing it; a narrowing connector proving no absence until it enumerates; a capped round proving none; a mass absence and an empty listing parking their rounds, parking again on resuming, and closing once accepted.
- **Checks**: tests state each rule above from SYNC; every step's store is written and self-checked. Broken by hand to see each fail: an absence found out of scope, a narrowed round without an enumeration dropping, a capped round dropping, no park, a resumed round drawing a new id, an out-of-scope create pushed, a delta leaving the coverage, the connector keeping out-of-scope members, a narrowing taking no margin, an `Add` pushed while the round stays parked.
