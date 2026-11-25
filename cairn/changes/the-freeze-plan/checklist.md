# The freeze checklist

The steps of the commit releasing storage-v1.0.0, sync-v1.0.0 and search-v1.0.0, and of io-pimdir 1.0.0 beside it, read on 2026-11-25 against the trees of that day. It replaces the list of cairn/log/2026-11-13-the-freeze-gate-is-rehearsed.md, whose steps named files the smaller-pimdir night of 2026-11-22 removed (queries/, GUIDE.md, checks/names.sh, checks/invariants.sh). The draft numbers below are those of the day; the freeze reads the last drafts, whatever their numbers then.

## Before the freeze commit

1. Every line of tasks.md sections 1 to 7 closed, and the stop rule of D5 met: two campaigns in a row with no spec break.
2. io-pimdir passes this tree: tests/pending_vectors.txt empty, every `_known_included` test of tests/generated passing with no known finding, the generator's own tests green, and checks/io-pimdir.rev naming that commit.
3. A rehearsal of steps 4 to 9 on a scratch copy of both trees, never in place, every check of pimdir's `nix flake check` and io-pimdir's suite green on it, as the 2026-11-13 dry run did.

## The pimdir freeze commit

4. Status lines: STORAGE.md `storage-v1.0.0, the base, requiring no other part, released together with the sync and search parts`; SYNC.md `sync-v1.0.0, requiring storage-v1.0.0, released together with it and the search part`; SEARCH.md `search-v1.0.0, requiring storage-v1.0.0, released together with the storage and sync parts`. conventions/gtd.md, which still requires storage-draft-17 and search-draft-16, requires storage-v1.0.0 and search-v1.0.0 under a gtd number of its own.
5. The names a program records: STORAGE §4.2 `format_version` is the major alone, `storage-v1`; SYNC §10 `sync_version` `sync-v1`; SEARCH §2 the index's `format_version` `search-v1`. Each sentence naming a draft as current (STORAGE §4.2 and §17, SYNC §10 and §12, SEARCH §2 and §12) names the release.
6. The sentences that hold while a part is a draft are rewritten for a release: STORAGE §4.2 (a draft's store opens under that draft alone), SYNC §10 (an engine refusing another draft's sync state), README.md's Status (its draft paragraph goes, the three versions in bold), OVERVIEW.md §1, AGENTS.md §2 (the relaxation ends: a change carries proposal.md and tasks.md, and cairn/spec/ is reconsidered).
7. checks/frozen.sha256 gains, by `bash checks/frozen.sh . --digest <path...>`: storage-v1.0.0 migrations/storage/0001_init.sql and payloads/*.v1.schema.json; sync-v1.0.0 every file of vectors/sync/ and vectors/schema/sync.schema.json; search-v1.0.0 vectors/search/store.json, the fixtures the search vectors name and the search schemas. checks/appended.py's lines freeze queries.json, refresh.json, chunks.json and extraction.json as intact prefixes (owner, 2026-11-25). Whether objects.json, summaries.json, payloads.json and versions.json join appended.py the same way is decided at the rehearsal (step 3): they are case lists a minor would append to.
8. vectors/manifest.json restated, vectors/README.md's format versions as they stand.
9. A log entry naming the release, and the note a draft user needs: sync until nothing is pending with the last draft binary; the release refuses every draft store, so a program built on a draft is reinstalled over a new store (README.md, Status).

## io-pimdir 1.0.0 beside it

10. `sql::FORMAT_VERSION` `storage-v1`, `SYNC_VERSION` `sync-v1`, `sql::search::FORMAT_VERSION` `search-v1`, spec/queries/storage/owner/init_store_meta.sql and spec/queries/search/init_index_meta.sql writing them, `FORMAT_DRAFT` retired or answering no draft, and the index's `draft()` (src/client/search.rs) reading a release by SEARCH §2's order, which answers nothing for one today.
11. spec/ vendored from the freeze commit, spec/REVISION naming it; Cargo.toml 1.0.0; CHANGELOG `[1.0.0]` with the date; README and cairn/spec naming the releases.
12. pimdir's checks/io-pimdir.rev names that io-pimdir commit, in a commit after the freeze commit, as every draft did.

## Push, CI, then tags (owner, 2026-11-25: never tag before CI is green)

13. Push pimdir master and io-pimdir master, no tag. Wait for pimdir CI (`nix flake check`, checks/tags.sh, checks/implementation.sh at the pinned commit) and io-pimdir CI (tests, msrv, the feature sets, the generator) green on those exact commits; run io-pimdir's release-on-demand workflow for the platform targets the Releases workflow builds, and wait for them green too.
14. Only then the tags: `storage-v1.0.0`, `sync-v1.0.0` and `search-v1.0.0` at the pimdir freeze commit (CI runs checks/tags.sh `--released` on their push), and `v1.0.0` at io-pimdir's release commit, whose Releases workflow publishes the crate (never `cargo publish` by hand). The semver-checks job starts on the first io-pimdir commit after 1.0.0 is on crates.io.

## Not in this freeze

The consumers (himalaya, cardamum, calendula, neverest, carillon, the Android app) stay on io-pimdir 0.20.x and move to 1.0 later (owner, 2026-11-25); the breaking lines they meet are listed in io-pimdir cairn/log/2026-11-25-the-public-api-for-one-zero.md and its CHANGELOG.
