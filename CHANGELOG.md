# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and each part adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html) under its own version, as README.md's Status section says. The detail of each change lives in [cairn/log](./cairn/log).

## [Unreleased]

## [storage-v1.0.0], [sync-v1.0.0], [search-v1.0.0] - 2026-11-26

The first release of the three parts, released together. A store, a sync state or an index a draft wrote opens under no release: README.md's Status says how a draft user moves to a new store.

### Added

- Added STORAGE.md, storage-v1.0.0: the store directory, its schema under migrations/storage, the payload schemas and the open contract.
- Added SYNC.md, sync-v1.0.0, requiring storage-v1.0.0: the sync engine over the store and its connector seam.
- Added SEARCH.md, search-v1.0.0, requiring storage-v1.0.0: the index and the query language.
- Added the vectors under vectors/, which an implementation passes to conform.
- Added checks/frozen.sh, checks/appended.py and checks/tags.sh, which hold the bytes and case lists a release froze.

[unreleased]: https://github.com/pimalaya/pimdir/compare/storage-v1.0.0..HEAD
[storage-v1.0.0]: https://github.com/pimalaya/pimdir/tree/storage-v1.0.0
[sync-v1.0.0]: https://github.com/pimalaya/pimdir/tree/sync-v1.0.0
[search-v1.0.0]: https://github.com/pimalaya/pimdir/tree/search-v1.0.0
