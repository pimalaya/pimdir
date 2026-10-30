---
cairn: log
change: each-part-is-versioned-apart
date: 2026-10-30
---

# Each part is versioned apart

The Versioning section of the pimdir stable-release plan. The three normative parts carried one draft number, `draft-04`, which was never tagged, while STORAGE is to freeze before SYNC and SEARCH.

- **Status lines**: STORAGE `storage-draft-05, the base, requiring no other part`; SYNC `sync-draft-05, requiring storage-draft-05`; SEARCH `search-draft-05, requiring storage-draft-05`.
- **STORAGE §4.2** (normative): the major is the store schema version; a minor adds a rule, a statement or a vector breaking no store; a patch is editorial.
- **README Status, AGENTS.md §2, OVERVIEW §11**: per-part versions and tags, `<part>-vX.Y.Z` once released (SEARCH's major the index schema version, SYNC's a breaking seam or engine change), one real upgrade cycle added to the STORAGE freeze gate, "stable in shape" dropped.

Tags are the user's: `draft-04` on 8b2e8b6, the text the old Status lines claimed; then `storage-draft-05`, `sync-draft-05` and `search-draft-05` once the changes targeting them have landed; `storage-v1.0.0` at the very end. No check guards a Status line.
