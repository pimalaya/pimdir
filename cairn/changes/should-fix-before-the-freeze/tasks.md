---
cairn: tasks
change: should-fix-before-the-freeze
---

# Tasks

## Store

- [x] `delete_collection` refuses while the collection holds a pending or parked queue row (decided: refuse, not park); `collections_keep_queued` in 0001_init.sql; STORAGE §14, GUIDE §8; checks/invariants.sh ("collection: a collection holding a parked action is not deleted")
- [x] Unknown payload `v` skipped; STORAGE §13, §15.2, §15.3
- [x] Derived prefixes reserved and escaped (`esc:`); STORAGE §9, §13, §16, GUIDE §11, schema comments; summaries.json case card-reserved-uid.vcf; checks/vectors.py checks every stated identity's key
- [x] Unicode version for case folding: 15.0.0, STORAGE Annex A.2 (A.6 reads A.2's mapping); vectors/README.md
- [x] queries/ status in STORAGE §4.4 and OVERVIEW §11: name, parameters and result columns bind, the text is reference; canonical `backfill_invitation` and `backfill_task_organisation` (the version bump landed with the-store-version-is-a-contract); checks/invariants.sh, checks/names.sh
- [x] Rebuildable overclaim in STORAGE §1, README, OVERVIEW §1: what re-sync restores and what it cannot, a rebuild only on the user's confirmation
- [x] Terminology: folders and files in STORAGE §2
- [x] Draft shims into one upgrade annex: moved out of this change to the-draft-shims-gather-in-one-annex, editorial and best done once the last draft schema edit has landed

## Sync

- [x] A second source's other message under a held Message-ID mints; SYNC §6, §9, STORAGE §9, GUIDE §11; vector 93 and checks/vectors.py
- [x] Events tied to commit; SYNC §5, GUIDE §10
- [x] Handle-less `Accepted` add; SYNC §4, §5, §11, GUIDE §10; vector 92 and checks/vectors.py

## Wording and checks

- [x] RFC 8174 boilerplate in STORAGE, SYNC, SEARCH, README; keyword audit (SYNC §5 rounds, STORAGE §11 and §11.1; the untestable page-size MUST left with the page table, conventions-leave-the-core)
- [x] Contradictions: AGENTS.md freeze criteria, GUIDE §11 against SYNC §8 (rekey match order, landed with a-rekey-parks-a-mass-absence), GUIDE §12 against STORAGE §11 (purge needs the same body); README's "stable in shape" and "recreated" were already gone
- [x] `v` on every vector file; a JSON Schema per format under vectors/schema/; checks/vectors.py validates (python `jsonschema` added to flake.nix)

## Search

- [x] `occurring_between` takes a zero-length occurrence at the range start; checks/invariants.sh and search case `date:2027-01-15` (item 22)
- [x] `horizon_left` only where a calendar item is reachable; SEARCH §8.1, GUIDE §15; checks/vectors.py re-derives it
- [x] `has:attachment`: the mark for mail, the `attachment` field (an `ATTACH` with `FILENAME` or `FMTTYPE`) for a calendar item; SEARCH §6, §8; search cases over item 23
- [x] The review's other SEARCH ambiguities: chunk offsets (a client of another implementation re-chunks), `id:` with digits alone, `linked:` role parsing; SEARCH §6, §8

- [x] Log entry; lands in storage-draft-05, sync-draft-05, search-draft-05
- [x] `nix flake check path:$PWD`

Followers, tracked in their repositories: io-pimdir (the trigger and the two backfill statements re-vendored and its hand-written backfills replaced; the escape when assigning a key; the minting of another message under a held Message-ID; a handle-less add; events after commit; unknown `v` skipped; vectors `v` read; `occurring_between`, `has:attachment`, `horizon_left`, `id:` in its search), every owner deleting collections (cancel first).
