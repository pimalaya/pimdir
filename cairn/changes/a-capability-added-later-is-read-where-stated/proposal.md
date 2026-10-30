---
cairn: change
id: a-capability-added-later-is-read-where-stated
status: landed
created: 2026-10-30
---

# A capability added later is read only where a row states it

## Why

Edit 5 of the pimdir stable-release plan (2026-10-30), from blocker 5 of the consolidated pimdir review. A declared source's missing row read as unsupported (STORAGE §15.6), and a declaration writes every Annex B capability. A capability Annex B added after an owner was written therefore read as `none` for every source that owner declared, and a newer producer refused actions the source performs. `x-vtodo` already needed a one-off exception for exactly this; the guard capabilities of a-source-states-its-write-guard would need another.

The plan chose the rule over a recorded Annex B revision on the declaration: a capability added after v1 is read as unsupported only where the declaring owner knew it, which a row says, since an owner writes every capability it knows, `none` included. No schema change.

## What

- STORAGE §15.6: a declaration writes every Annex B capability the owner knows; a missing row means unsupported for the base set only; a capability added after the base set is read only where a row states it, so a declared source with no row for it is neither supported nor refused there and nothing gates an action by it; an intent naming it has no candidate there. `x-vtodo` is read the same way.
- Annex B: its current names form the base set; a name added after `storage-v1.0.0` is marked with the version that added it.
- GUIDE §13: the producer's gate and the declaration follow.

## Lands in

storage-draft-05.

## Check

None in this repository: the statements already answer the rows (`load_capabilities`, `load_item_capabilities`), and the reading is the producer's gate and the owner's backstop, which io-pimdir tests. The rule has no capability to bite on until Annex B adds one after v1; the first one to arrive (the guard names of a-source-states-its-write-guard) carries the vector.
