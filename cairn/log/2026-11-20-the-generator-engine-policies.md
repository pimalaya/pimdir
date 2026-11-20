---
cairn: log
change: the-freeze-plan
landed: 2026-11-20
---

# The generator's engine, fifth part: the conflict policies

The fifth part of plan 2's "The scripted remote states", of cairn/changes/the-freeze-plan. No part of the standard moves.

- **The policies** (generator/src/engine.rs, generator/src/remote.rs, SYNC §5, §9), a remote's `policy` and whether its pages carry bodies: `PreferRemote` pulls an edit made on both sides, the item emptied when the member carries no body, the local edit kept as a retained item; `PreferLocal` keeps the member's carried body as a retained item, moves the base onto it at the observed revision and pushes the local body gated on that revision; `KeepLocal` does the same over a revision the server alone moved, the store being authoritative (vectors 174 and 175); a body nobody has read is recorded in conflict at the observed revision whatever the policy. A kept body is a retained item keyed `dup:`, the link id, `#` and the binding's handle, minted again while held, drawing a `seq` of its own, retained by the binding's source, reported `Overruled` with its key.
- **A history** of five address books, one per policy and unread case, each through a first round, a server edit (with a local one where the policy needs both), its settlement and a run with nothing left to do.
- **The feed of an empty store** answers no stamp, which the oracle now states.
- **Checks**: tests state each settlement from SYNC; each step's store is written and self-checked. Broken by hand to see each fail: `PreferRemote` dropping the local edit, `KeepLocal` acting on local edits alone, an unread body kept rather than recorded.
