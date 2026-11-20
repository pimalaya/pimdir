---
cairn: log
change: the-freeze-plan
landed: 2026-11-20
---

# The generator's engine on sync format 11

The engine model follows the rules sync format 11 pins (cairn/log entries of 4409276) and the one the lead decided on vector 182, of cairn/changes/the-freeze-plan. No part of the standard moves.

- **A change is derived before the fold** (generator/src/engine.rs, SYNC §5, vector 182): what the fold of a pull or a join leaves a binding owing, the item's body a collection's `prefer-existing` kept over the member's, is pushed by the source's next run, never by the run that pulled. The model pushed it in the same run.
- **The unlisted report** (SYNC §5, sync format 11, vectors 107 and 134): a closing round that is capped, or narrowed handing no enumeration, reports in `Run::unlisted` how many based bindings of its scope it left unstamped, counted as its deletes are; a parked round, an enumerating one and a delta report none.
- **A join** (SYNC §5, §6, §9, vectors 184, 185, 187, 188): a join is reported `Added` alone, never `Created`, its folded flags no `FlagsChanged`; a carried diverging body is settled by the collection's policy, an unread one recorded in the item's conflict with no `conflict_object`. The upgrade of a binding naming a revision and no body over an item holding one now reads it into the base, and that is all unless an item conflict waits for that body (vector 133): then a body equal to the item's clears the conflict, the base and the shared body taking it (vector 188); another is settled by the policy as a carried one would have been, `manual` landing it as the `conflict_object`, `prefer-incoming` and `prefer-existing` keeping the body not adopted over the handle (vectors 90, 91).
- **The history** of several sources gains, per address book, `b`'s next run pushing what its fold left it owing, and two address books where `b` joins two cards unread and its upgrade reads them, one equal to the item's, one differing, under `manual` and `prefer-incoming`.
- **Checks**: tests state each rule above from SYNC; every step's store is written and self-checked. Broken by hand to see each fail: a fold's debt pushed in the same run, no unlisted report, an equal body read as a divergence, the upgrade ignoring the policy.
