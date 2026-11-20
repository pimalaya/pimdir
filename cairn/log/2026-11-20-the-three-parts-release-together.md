---
cairn: log
change: the-freeze-plan
landed: 2026-11-20
---

# The three parts release together

The owner's ruling of 2026-11-20 (cairn/changes/the-freeze-plan, "Search in v1", D3): SEARCH is released with STORAGE and SYNC, reversing README.md's "SEARCH is released later". It is the first spec change after the draft-14 tags, so it opens the next draft: **storage-draft-15**, **sync-draft-15** and **search-draft-15**, which the rest of the freeze plan's spec changes join without another bump.

## What moved

- The Status lines: STORAGE and SYNC are released together with the search part, SEARCH together with the storage and sync parts.
- README.md's Status: the three parts are released together, `storage-v1.0.0`, `sync-v1.0.0` and `search-v1.0.0` tagged at one commit, once io-pimdir passes the tree at the drafts to be released.
- AGENTS.md §2: the three parts are released together, their first releases tagged at one commit. Its last section names generator/ as the standard's own test tooling (D1), implementing no profile.
- The draft names, as the draft-14 bump moved them: the Status lines, README.md, AGENTS.md, STORAGE §4.2, §14 and §17, SYNC §10 and §12, SEARCH §2 and §12, GUIDE §1; `init_store_meta` writes `storage-draft-15`, `init_index_meta` `search-draft-15`; checks/invariants.sh refuses a draft-14 store under draft-15, and the scenarios stamping a draft's name, the sync version and the index version name draft-15.
- conventions/gtd.md requires the new drafts, so it moves to **gtd-draft-05**, its rules unchanged.

## Guards

- checks/names.sh: every Status line, README.md's Status and every document name the drafts the Status lines state.
- checks/tags.sh: with `--released`, a release fails while any of the three parts' version has no tag, SEARCH's included.
- The freeze checklist gaining `search-v1.0.0`, and checks/frozen.sha256 the search statements and signatures, stay open lines of the freeze plan (5b).

## Consequences

Every store and sync state of draft-14 is refused, never migrated, and an index of draft-14 is rebuilt: each app rebuilds its store once it takes the io-pimdir following this draft.
