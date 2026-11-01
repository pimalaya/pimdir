---
cairn: delta
change: two-silent-losses-fold-into-draft-08
---

## ADDED Requirements

### Requirement: SYNC §7 A resolution names its conflict
An `Edit` without `overrule` SHALL settle a conflict only as a person's resolution stating `resolves`, the diverging bodies it was decided over. Meeting the item's conflict or its binding's, it MUST be refused, staging nothing, unless `resolves` names the `conflict_object` of each conflict it meets; stating `resolves` and meeting none, it MUST be refused the same way. A conflict whose `conflict_object` is `NULL` is named by no resolution.

#### Scenario: an ordinary edit over an item conflict
- GIVEN the store of vectors 118 to 123, the item at c3 conflicted over c2
- WHEN an `Edit` through b writes c4 over c3, stating no `resolves`
- THEN it fails and the rows stay as they were (vectors/sync/124)

#### Scenario: a resolution of another conflict, of none, of an unread body, of one of two
- GIVEN a conflict standing over another body than `resolves` names, no conflict, a conflict with no `conflict_object`, or an item and a binding both conflicted
- WHEN an `Edit` stating `resolves` runs
- THEN it fails and the rows stay as they were (vectors/sync/125, 126, 128, 129); through a conflicted binding without `resolves` likewise (127)

#### Scenario: a person's resolution
- GIVEN the store of 118 to 123
- WHEN an `Edit` stating `resolves` c2 runs through either source
- THEN the item's conflict is settled as SYNC §7 says (vectors/sync/118 to 123)

### Requirement: STORAGE §15.3 The update's resolves
The `update` payload at v 1 SHALL be `{ "v": 1, "seq": n, "object": hash, "if_match": hash?, "resolves": [hash…]? }`. A producer deciding a conflict states `resolves`, and MUST NOT state it on any other update. An update meeting a conflict MUST be parked, naming it, unless `resolves` names each conflict's `conflict_object`; one stating `resolves` and meeting none MUST be parked. While this part is a draft, a payload's shape at its `v` is edited in place.

#### Scenario: resolves is a set of names
- GIVEN an update stating `resolves` as an empty array, one name, a name twice, a path or `true`
- WHEN it is validated against payloads/update.v1.schema.json
- THEN it is malformed; one or two distinct names are valid (vectors/payloads.json)

### Requirement: STORAGE §5 A name held is verified
A writer finding its final name held, or skipping its write because the name or its row is there, MUST verify the file there against its name before it keeps it. An owner SHALL move a file that fails into quarantine/ as §7 does and move again; a producer SHALL fail its write and enqueue nothing.

#### Scenario: a fetch meets a failing file under its name
- GIVEN the store of vector 30, the file under c2's name holding bytes that fail it
- WHEN the Full upgrade fetches c2
- THEN the item and the base name c2 and the file under its name hashes to it (vectors/sync/130)

### Requirement: STORAGE §5 The exclusive create and copy
A writer MAY use an exclusive create of the final name, a copy of the temporary's bytes into it, its `fsync` and the temporary's unlink, only where no atomic no-replace move is offered or allowed. A copy that fails unlinks the part it created.

## MODIFIED Requirements

### Requirement: STORAGE §5 Android's no-replace move
*Note:* On Android the no-replace move is `renameat2` with `RENAME_NOREPLACE` from API 30, and the exclusive create and copy before it and wherever `renameat2` answers `ENOSYS` or `EINVAL`.
