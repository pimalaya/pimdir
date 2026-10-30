---
cairn: delta
change: each-part-is-versioned-apart
---

## MODIFIED Requirements

### Requirement: STORAGE, SYNC and SEARCH Status lines
Each normative part SHALL name its own version in its Status line, and the versions of the other parts it requires: STORAGE `storage-draft-05`, requiring no other part; SYNC `sync-draft-05`, requiring `storage-draft-05`; SEARCH `search-draft-05`, requiring `storage-draft-05`. A released part is versioned `<part>-vX.Y.Z`, its major following its artefact (STORAGE: the store schema version; SEARCH: the index schema version; SYNC: a breaking change to the connector seam or the engine), a minor adding a rule, a statement or a vector breaking nothing, a patch editorial.

#### Scenario: an implementation states its conformance
- GIVEN io-pimdir implementing the store and the engine and no index
- WHEN it states what it conforms to
- THEN it names `storage-draft-05` and `sync-draft-05`, each part on its own
