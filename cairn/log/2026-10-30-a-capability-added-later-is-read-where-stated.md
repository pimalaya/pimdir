---
cairn: log
change: a-capability-added-later-is-read-where-stated
date: 2026-10-30
---

# A capability added later is read only where a row states it

Edit 5 of the pimdir stable-release plan. A declared source's missing row read as unsupported, so every capability Annex B adds after an owner was written would read as `none` for the sources that owner declared, and a newer producer would refuse what they do; `x-vtodo` already needed an exception for it.

- **STORAGE §15.6** (normative): a declaration writes every Annex B capability the owner knows; a missing row means unsupported for the base set only; a capability added after the base set is read only where a row states it, gating nothing where none does and offering no intent candidate there; `x-vtodo` is read on the same terms.
- **STORAGE Annex B** (normative): its names form the base set; a later name is marked with the version adding it.
- **GUIDE §13** (informative): the gate and the declaration.

No schema or statement changes, so no check here can fail without it: the reading is the producer's gate and the owner's backstop, which io-pimdir tests, and the first capability added after v1 (a-source-states-its-write-guard's guard names) brings the vector.
