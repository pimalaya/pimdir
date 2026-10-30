---
cairn: delta
change: every-vocabulary-is-open-or-closed
---

## ADDED Requirements

### Requirement: STORAGE §13 Closed and open vocabularies
A closed vocabulary SHALL be held by a schema `CHECK`, a value outside it refused at the write and a new value being a new schema version; an open one SHALL be checked by no constraint, and a reader MUST read a value it does not know as §13 says for that column. Closed: `kind`, `level`, `deleted` and `conflicted`, `conflict`, `support`, `origin`, `item_reference.role`. Open: `collections.role`, `action`, `capability`.

#### Scenario: a fifth kind is refused
- GIVEN a store at the canonical schema
- WHEN `set_collection_kind` declares a collection `text/x-vlist`
- THEN the write fails and no collection takes that kind (checks/invariants.sh)

#### Scenario: a role the registry adds later
- GIVEN a mail collection
- WHEN `set_collection_role` records `snoozed`
- THEN the role is stored, and a reader not knowing it reads none

### Requirement: STORAGE §6 Reconciliation repairs what a closed vocabulary refuses
Reconciliation's repair step SHALL run `repair_levels` (an earlier draft's `level` 0 to 1) and `repair_kinds` (a media type outside the set to `''`) before the rebuild.

#### Scenario: an earlier draft's 0
- GIVEN a version 1 store an earlier draft wrote, its ladder taking 0 and one row at 0
- WHEN `items` is rebuilt before the repair
- THEN the rebuild fails on the `CHECK` and the store is unchanged; after `repair_levels` it succeeds and the row reads 1 (checks/invariants.sh)

## MODIFIED Requirements

### Requirement: STORAGE §13 `level`
`level` SHALL be `1` meta or `2` full, by constraint. A reader meeting a `0` in a version 1 store not yet reconciled reads it as `1`.

### Requirement: STORAGE §14 A collection's role
The role vocabulary is open: `set_collection_role` sets or clears it, an owner writing only on a declared collection and only a role of its kind's vocabulary, and a reader MUST read a role it does not know, or one of another kind's vocabulary, as none.
