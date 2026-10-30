---
cairn: change
id: each-part-is-versioned-apart
status: landed
created: 2026-10-30
---

# Each part is versioned apart

## Why

The Versioning section of the pimdir stable-release plan (2026-10-30). One draft number pinned STORAGE, SYNC and SEARCH together, so STORAGE could not freeze while SYNC and SEARCH stay draft (README Status already planned a freeze by part), and `draft-04`, which the Status lines claimed, was never tagged. README also called schema version 1 "stable in shape" while 0001_init.sql was edited on 2026-10-27, 2026-10-28 and 2026-10-29.

## What

- STORAGE, SYNC and SEARCH are versioned apart; README, OVERVIEW and GUIDE are informative and carry no version.
- Tags `<part>-draft-NN`, later `<part>-vX.Y.Z` (`storage-draft-05`, `sync-v1.0.0`).
- Majors follow each part's artefact: STORAGE major N is store schema `user_version` N, SEARCH's major the index schema version, SYNC's a breaking connector-seam or engine change. A minor adds a rule, a statement or a vector breaking nothing; a patch is editorial.
- Each Status line names its own version and the versions of the others it requires: `storage-draft-05, the base, requiring no other part`; `sync-draft-05, requiring storage-draft-05`; `search-draft-05, requiring storage-draft-05`. io-pimdir states its conformance per part.
- README Status says the above, drops "stable in shape", adds one real upgrade cycle to the STORAGE freeze gate; AGENTS.md §2 follows; OVERVIEW §11 says each part has a version.

## Tags (the user's to make)

1. `draft-04` on 8b2e8b6, the text the Status lines claimed, which closes the global scheme.
2. `storage-draft-05`, `sync-draft-05` and `search-draft-05` once every change targeting them has landed (see the plan's waves). Tagging one earlier fixes its text, and a later change then bumps that part to `-draft-06`.
3. `storage-v1.0.0` only at the very end, after one real upgrade cycle.

## Lands in

storage-draft-05, sync-draft-05, search-draft-05 (the Status lines themselves).
