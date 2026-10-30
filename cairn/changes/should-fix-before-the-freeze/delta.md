---
cairn: delta
change: should-fix-before-the-freeze
---

## MODIFIED Requirements

### Requirement: STORAGE §14 Deleting a collection
`delete_collection` SHALL NOT drop a pending or parked queue row: it is refused while the collection holds one, which the schema holds (`collections_keep_queued`).

### Requirement: STORAGE §15.2 An unknown payload version
An owner meeting a payload `v` it does not know SHALL skip the row, as it skips a kind it does not know.

### Requirement: STORAGE §9 and Annex A Derived prefixes are reserved
A hint beginning with `hash:`, `alt:`, `dup:`, `part:` or `file:` SHALL be escaped before it is used as a link id, `esc:` and the hint, `esc:` reserved with them, so no stated identity reads as writer-derived.

### Requirement: SYNC §9 A second source's message under a held Message-ID
A message a second source holds under a Message-ID the store holds with another body SHALL be minted as a duplicate, never discarded.

### Requirement: SEARCH §8 A zero-length occurrence at the range start
An occurrence of zero length starting at a range's start SHALL fall in the range.
