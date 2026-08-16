---
cairn: log
change: adopt-cairn
landed: 2026-08-16
---

# Adopt Cairn, in its draft-format form

The repositories this format binds all follow Cairn already, so a change to the format was recorded in every repository except the one that defines it. This closes that gap, with two deviations that are honest about what a specification repository is.

## What landed

`cairn/` with `spec/`, `changes/` and `log/`, a `cairn.toml` pinning `spec_version = "0.1.0"`, `AGENTS.md` carrying the activation and the two deviations, and `CLAUDE.md` pointing at it.

**`cairn/spec/` is empty on purpose.** SPEC.md is this repository's current truth, and other repositories cite it by section: io-pimdir's spec-fidelity capability checks its SQL against migrations/ and queries/, and calendula's backends capability names §13. A capability file restating any of that would be a second home for one rule, and the first edit that touched only one of them would start the drift. A change is therefore folded into SPEC.md itself, which is the same discipline under a different filename.

**A log entry is the whole obligation while the format is `draft`.** The schema is edited in place until version 1 is frozen (§6), nothing depends on a frozen shape, and a proposal plus a task list per change does not repay its cost at this stage. A change folder stays available for intent worth reviewing before the edit. The forcing rule is untouched: SPEC.md moves, and the log says so.

Both deviations are written as scoped to the draft, and [changes/adopt-cairn/tasks.md](../changes/adopt-cairn/tasks.md) carries the single standing task to end them at the freeze.

## Capabilities moved

None. `cairn/spec/` is empty by the decision above, and SPEC.md is unchanged by this entry.
