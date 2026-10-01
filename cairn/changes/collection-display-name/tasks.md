---
cairn: tasks
change: collection-display-name
---

# Tasks

## Landed in this repository

- [x] queries/storage/owner/set_collection_name.sql.
- [x] STORAGE.md §14: a name is a label, never an address, and who keeps it current.
- [x] STORAGE.md §9.2 and GUIDE.md §8 point at the column and the statement.
- [x] checks/invariants.sh: the seed, the move, and what does not move with it.
- [x] Log entry.

## Left to io-pimdir

Its own change, with its own log entry and a CHANGELOG line under `### Added`.

- [x] Re-vendor spec/queries/storage/owner/ so tests/spec_drift.rs stays green.
- [x] `PimdirSourceStore::set_collection_name`, beside `ensure_collection` and `set_collection_account`.
- [x] Tests: the name moves independently of the id, and moving it stamps the collection in the change feed.

## Left to neverest

- [x] Key collections on the backend id rather than the display name.
- [x] Keep `DAV:displayname` instead of overwriting it with the path segment.
- [x] Call `set_collection_name` beside every `ensure_collection`.
