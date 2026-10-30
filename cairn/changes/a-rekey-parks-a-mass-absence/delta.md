---
cairn: delta
change: a-rekey-parks-a-mass-absence
---

## ADDED Requirements

### Requirement: SYNC §8 A rekey missing most members parks
A rekey whose listing leaves more than half of at least 20 based bindings of the source resolving to no member MUST NOT be written unless the run carries `accept_absences`; it reports the absent and the bound counts.

#### Scenario: a truncated listing of a renumbered collection
- GIVEN 20 based bindings and a rekey listing naming 2 of them
- WHEN the rekey runs without `accept_absences`
- THEN nothing is written and the run reports 18 absent of 20 bound (vectors/sync/89)
