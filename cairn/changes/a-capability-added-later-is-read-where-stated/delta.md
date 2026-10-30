---
cairn: delta
change: a-capability-added-later-is-read-where-stated
---

## MODIFIED Requirements

### Requirement: STORAGE §15.6 Declaring
A declaration MUST write every Annex B capability the owner knows of the kinds the source syncs, `none` included. A capability of Annex B's base set a declared source has no row for, or a `none` row, is unsupported.

## ADDED Requirements

### Requirement: STORAGE §15.6 Capabilities added later
A capability Annex B adds after its base set SHALL be read only where a row states it: a declared source with no row for it neither supports nor refuses it, and neither the producer's gate nor the owner's backstop gates an action by it there; an intent it names has no candidate there.

#### Scenario: an older owner's declaration
- GIVEN a source declared by an owner predating `contacts.card.guard`, a capability added after `storage-v1.0.0`
- WHEN a newer producer enqueues an `update` of a card that source binds
- THEN the gate reads no row for the guard, refuses nothing by it, and enqueues
