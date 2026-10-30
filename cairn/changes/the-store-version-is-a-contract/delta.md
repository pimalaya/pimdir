---
cairn: delta
change: the-store-version-is-a-contract
---

## MODIFIED Requirements

### Requirement: STORAGE §4.2 Schema version
`PRAGMA user_version` and `store_meta.version` SHALL agree and SHALL move together, only in the transaction applying a migration. This part's major version is the schema version. While this part is a draft, version 1 is edited in place and a store an earlier draft wrote is reconciled to it, never recreated; once version 1 is released, 0001_init.sql never changes and every schema change is a migration to the next version.

### Requirement: STORAGE §6 Migrations
An owner opening a store SHALL, in order: refuse a store above the highest version it knows, naming both, never reconciling, migrating, rebuilding nor writing it, whatever the profile; reconcile a version 1 store whose shape differs from 0001_init.sql alone, before any migration; run each migration above the store's version in its own transaction, setting `user_version` and `store_meta.version` (`set_store_version`). No implementation rebuilds a store it cannot read. A migration MUST preserve every row of every table and the meaning of every column it keeps. A reader or a producer meeting a store below its version, or an unreconciled version 1 store, reads a missing column as `NULL` and a missing table as empty. While draft, an owner MUST reconcile an earlier draft's store or refuse it naming what it lacks, never recreating nor deleting it.

#### Scenario: a migration stamps its version
- GIVEN a store initialised by `init_store_meta` at version 1
- WHEN a migration runs `set_store_version` with 2
- THEN `load_store_meta` answers version 2 (checks/invariants.sh)

#### Scenario: an earlier draft's store_meta is reconciled
- GIVEN a version 1 store whose `store_meta` lacks `derivation`
- WHEN it is compared with 0001_init.sql and rebuilt
- THEN `store_meta` differs before and not after, and `derivation` reads 1 (checks/invariants.sh)

## ADDED Requirements

### Requirement: STORAGE §6 and Annex A Derivations are revised
Annex A SHALL carry a revision, 1 today, bumped in a minor version of this part by a change to what a writer derives. `store_meta.derivation` SHALL record the revision a store was derived under, written by `init_store_meta`. An owner at a later revision MUST re-derive the columns the revisions between changed from every held body, then record its own with `set_derivation`; until recorded the re-derivation is owed. `set_derivation` never lowers the revision.

#### Scenario: a revision is never lowered
- GIVEN a store at derivation 2
- WHEN `set_derivation` runs with 3 then with 1
- THEN `load_store_meta` answers 3 (checks/invariants.sh)
