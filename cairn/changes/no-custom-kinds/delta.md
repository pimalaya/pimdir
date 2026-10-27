---
cairn: delta
change: no-custom-kinds
---

## ADDED Requirements

### Requirement: STORAGE §4.3 The set of kinds is closed
A collection's `kind` SHALL be `message/rfc822`, `text/vcard`, `text/calendar` or `application/octet-stream`, or `''` until `set_collection_kind` declares it. Any other value MUST be refused by the schema. A new kind is a change to this standard, carrying its summary table, its Annex A section and its vectors. The `x-` prefix names capabilities (§15.6), reference roles (§14.2) and queue actions (§15.3), never a kind.

#### Scenario: a fifth kind is refused
- GIVEN a store at the canonical schema
- WHEN `set_collection_kind` declares a collection `text/x-vlist`
- THEN the write fails on the `collections` check and the collection keeps its empty kind (checks/invariants.sh)

## MODIFIED Requirements

### Requirement: STORAGE §1 Goals
**Generic**: one store for every kind the standard names, keyed by media type. The set is closed: it grows by a change to the standard, never by a writer.

### Requirement: STORAGE §13 Encodings
`kind` (TEXT, on `collections`, and `from_kind`, `to_kind` on `item_reference`): one of the four media types of §4.3, `''` on a collection not yet declared.
