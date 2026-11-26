---
cairn: log
change: the-v1-release
landed: 2026-11-26
---

# The v1 release

storage-v1.0.0, sync-v1.0.0 and search-v1.0.0, released together at one commit (cairn/changes/the-freeze-plan, checklist.md steps 4 to 9), the reference implementation io-pimdir 1.0.0 passing every check and vector at them. They are the drafts storage-draft-19, sync-draft-16 and search-draft-20 with no rule moved: the Status lines, the names a program records and the sentences that held while a part was a draft.

## What moved

- **The names a program records.** STORAGE §4.2 `format_version` `storage-v1`, the major alone; SYNC §10 `sync_version` `sync-v1`; SEARCH §2 the index's `format_version` `search-v1`. STORAGE §4.2, §6 step 2 and §14, SYNC §10 and SEARCH §2 state a draft's store, sync state and index as refused by every release (an index rebuilt by an indexer); STORAGE §17, SYNC §12 and SEARCH §12 state conformance as `storage-v1.0.0 owner, sync-v1.0.0 engine`. Guarded by vectors/versions.json (the order of a draft against a release) and io-pimdir's store_version and search suites.
- **What a draft allowed.** STORAGE §4.2 no longer edits 0001_init.sql in place nor keeps the three compatibility versions at 1; README.md's Status, OVERVIEW.md §1 and AGENTS.md §2 follow (a change now carries proposal.md and tasks.md; cairn/spec/ stays empty, the three documents being the spec).
- **What the release froze.** checks/frozen.sha256 holds 379 files: 0001_init.sql, the v1 payload schemas, the schemas of objects, payloads, summaries and versions, every sync case and its schema, the search store and schemas, every fixture a case names. Eight case files are held to an intact prefix by checks/appended.py: objects.json `/objects`, payloads.json, summaries.json and versions.json `/cases` (owner, 2026-11-26), search queries.json `/cases` and `/occurrences`, refresh.json, chunks.json and extraction.json `/cases`. A comment edited in 0001_init.sql, a case edited or removed and a fixture edited each fail; a case appended passes.
- **checks/tags.sh** owns vectors/versions.json and its schema for STORAGE and search-extraction.schema.json for SEARCH, which no part owned: an edit to either after its tag passed.
- conventions/gtd.md requires storage-v1.0.0 and search-v1.0.0 under gtd-draft-06, its vectors passing checks/vectors.py; its text was not reread against storage-draft-18 and -19 nor search-draft-17 to -20.

## For a draft user

A store a draft wrote opens under no release. Sync it until nothing is pending with the last draft binary, then move its directory aside and let a release's engine create and sync a new one (README.md, Status).
