---
cairn: log
change: audit-2026-11-12
landed: 2026-11-13
---

# The freeze gate is rehearsed

The proof lines of the audit of 2026-11-12 (cairn/changes/audit-2026-11-12, phase 2, the gate): what life after version 1 asks of a migration and of an older program, held by checks before the tags rather than after, and a dry run of the freeze commit on a scratch copy. Nothing is tagged and no part's version moves. The text lines of the same day are cairn/log/2026-11-13-draft-10-text-and-rules.md.

## Rules and their checks

- **V1, a migration that rebuilds a table** (STORAGE §6, §16, §18; GUIDE §3). A rebuild never runs in one transaction with foreign keys on. The runner sets foreign keys off before the transaction and on after it, and reads `foreign_key_check` (no row) and `integrity_check` (`ok`) before the commit. The script creates the new table, copies by named columns, drops, renames, creates again the table's indexes and triggers, drops before and creates again after every trigger and view of another table naming it, and keeps the `sqlite_sequence` row of an `AUTOINCREMENT` table. A closed vocabulary may grow instead by an edit of its `CHECK` under `writable_schema`, foreign keys on, the connection out of defensive mode for that transaction. Check: checks/rehearsal/, which never ships under migrations/: populate.sql (a released version 1 store with a row in every table, both sequences above every id held), additive.sql, rebuild.sh (prints the rebuild of a table from the store's own text, so it follows 0001_init.sql while that is edited), check.sql, and run.sh, which runs four migrations from a fresh copy each and is called by checks/invariants.sh on the current SQLite and by checks/floor.sh on 3.18.2. After the additive one, the rebuild of `collections` (a fifth kind) and of `queue`, and the `CHECK` edit, it asserts every row of every table by the columns it had, every schema object under its text, both sequences, the stamp at version 2, a clean `foreign_key_check` and `integrity_check`, a rename still cascading, and the next queue id and placement id above every one handed out; the fifth kind taken and a sixth refused; the `CHECK` edit refused in defensive mode with the store unmoved. The fourth is the forbidden form, which must not commit with every row.
- **V2, a store above a program's version** (STORAGE §4.2, §18; GUIDE §2; OVERVIEW §1). A released reader or producer judges such a store by six columns of `store_meta` and nothing else of the schema: `format`, `format_version` (`storage-v` and the version, a draft's name refused), `version` against `user_version`, `read_version`, `produce_version` for a producer, `hash_algo`. The six never change name, type nor meaning. A table, a column, an index, a trigger or a view it does not know is a later version's, never damage. The text of triggers and views is compared against a version the program knows alone: below SQLite 3.31 a store from elsewhere above its version is refused or confirmed by the user, and from 3.31 `trusted_schema` needs no comparison. That is the smallest rule found sound: a later version may rewrite a trigger version 1 created, so no comparison of version 1's objects survives a migration. Check: the scenario "released: ..." of checks/invariants.sh, eight assertions on a synthetic version 2 store holding a table, an index, a column, a trigger and a view version 1 does not know, stamped (2,1,1), (2,2,1) and (2,1,2) for a reader, a producer and an owner of version 1, then of version 2; a draft's name and a `user_version` disagreeing refused; a version 1 reader's statements answering their rows over it.
- **V3, the gate holds after the freeze.**
  - checks/tags.sh takes `--released`: a normative part whose version has no tag then fails, a draft's as a release's. Without the flag it passes as before, and CI passes the flag only on the push of a tag whose name holds `-v` (.github/workflows/tests.yml), so no draft push changes.
  - checks/names.sh reads a released Status line: `storage-v1.0.0` is a version, and the name a new store records is its major alone, `storage-v1` (the same for the index). It read an empty version before.
  - checks/names.sh compares every vector format `v` a document states with the `const` of its schema: the list of vectors/README.md for the eight formats, SYNC §11, SEARCH §11.
  - checks/names.sh fails on a version a document names that is neither its part's Status version, the first release, nor one of two past drafts listed for the fact they record. The dry run found this hole: with the Status lines moved, nine sentences still named the drafts and every check passed.
  - checks/frozen.sh with checks/frozen.sha256, a flake check: each line a SHA-256 and a path, or a path, `#` and a statement's name for one row of queries/signatures.json. Empty today, with a comment saying what the freeze adds; `--digest` prints the lines.
  - checks/implementation.sh fails when io-pimdir, at the pinned commit, lists a vector case in tests/pending_vectors.txt.
- **V8, the ledgers.** Closed by a dated note: performance-audit-2026-11-05/tasks.md lines 26 (the per-status scenario, see the other entry) and 42 to 45 (landed or dropped by storage-draft-09), refcount-floor/tasks.md:23, spec-algorithm-audit/tasks.md:33, created-at-stamped/tasks.md:17, a-delivered-create-waits-for-its-arrival/tasks.md:20. Reopened for the Android app alone, each with a note: audit-2026-10-31/tasks.md:105 (line A5) and :108 (line A1). Each line's text was read before it was touched.

Removed again in a scratch copy, each failed its check: the drop of the dependents (the rename fails on a current SQLite), the kept sequence (the next queue id is one already handed out), the indexes and triggers created again, a `CHECK` edit missing its text, `set_store_version` keeping a draft's name, a stated vector `v`, a released Status line beside a draft's marker.

## What the rehearsal showed

On SQLite 3.50.4 and on 3.18.2 alike, the rebuild run in one transaction with foreign keys on commits with 0 of 9 items and 0 of 2 queue rows, `foreign_key_check` empty and `integrity_check` answering `ok`. The audit had seen it fail on a current SQLite: that was the rename refusing a schema whose triggers name the dropped table. A script written as §6 now asks, dropping those triggers first, loses the rows silently on a current SQLite too. Foreign keys off before the transaction is the only guard, on every SQLite.

## The freeze dry run

On a scratch copy of the tree (2026-11-13), never in place, with no git write: the Status lines set to `storage-v1.0.0` and `sync-v1.0.0`, `init_store_meta` to `storage-v1`, README's Status, then every check.

What broke, first pass:

- checks/invariants.sh, four scenarios. Three wrote the draft's name out (the stamp of a new store, the draft-alone rule, the sync version beside it) and one, new in this batch, took a fresh store for a draft's. Defects of the checks: the scenarios now read the name off `init_store_meta` and run the released rule once it is a release's, so the freeze edits none of them.
- Nothing else, which was the defect: nine sentences still named `storage-draft-10` and `sync-draft-10`. checks/names.sh now fails on them.

Second pass, those sentences replaced and checks/frozen.sha256 filled (217 lines: 0001_init.sql, the v1 payload schemas, every row of queries/signatures.json under storage/): `nix flake check` passed whole. On that copy, a comment edited in 0001_init.sql, a parameter added to a frozen signature, a frozen statement removed and a v1 payload schema edited each failed checks/frozen.sh, and a statement added passed.

Not run: checks/tags.sh against a release tag, which needs the tag (on the repository as it stands, `--released` fails on the three untagged parts, as meant); checks/implementation.sh, which needs io-pimdir following this tree.

The freeze commit's checklist:

1. io-pimdir passes this tree, its tests/pending_vectors.txt empty, and checks/io-pimdir.rev names that commit.
2. Status lines: STORAGE.md `storage-v1.0.0`, SYNC.md `sync-v1.0.0, requiring storage-v1.0.0`; SEARCH.md and conventions/gtd.md require `storage-v1.0.0`.
3. queries/storage/owner/init_store_meta.sql writes `storage-v1`. No vector and no signature moves by it.
4. README.md's Status names the three versions in bold and loses its draft paragraphs.
5. Every sentence checks/names.sh then lists: STORAGE §4.2, §14 and §17, SYNC §10 and §12, GUIDE §1, AGENTS.md §2.
6. The sentences beginning "while this part is a draft", which no check reads: STORAGE §4.2, §6 and §15.3, SYNC §10, README, OVERVIEW §1, GUIDE §2 and §3, and AGENTS.md §2, whose relaxation ends for a released part.
7. checks/invariants.sh: the literal `sync-draft-10` given to `set_sync_version`, cosmetic.
8. checks/frozen.sha256: `bash checks/frozen.sh . --digest migrations/storage/0001_init.sql payloads/*.v1.schema.json 'queries/signatures.json#storage/*'`, appended.
9. The owner's tags, at that one commit: `storage-v1.0.0`, `sync-v1.0.0`, and `search-draft-10`, which was never tagged and which `tags.sh --released` asks for.
10. The note a draft user needs: sync until nothing is pending with the last draft binary, the release refusing the store.

## Left

- **The owner epoch** waits for after v1 (decided Q9); the rehearsal's rebuild is the route it would take if it needed one.
- **V2 in the implementations.** io-pimdir calls another `user_version` damaged and the Android app throws; the scenario models the rule, and only they can run it.
- **A rebuild's script is generated.** rebuild.sh reads the table's text off the store; a shipped migration writes it out, and is rehearsed as written when one exists.
- **The frozen list for sync-v1.0.0** holds nothing of its own, its seam being prose and vectors that checks/tags.sh holds to the tag; whether the sync vectors and their schema belong in checks/frozen.sha256 is the owner's.
- **io-pimdir a-page-lands-in-few-statements/tasks.md:18** is io-pimdir's ledger.

Checked on the working tree (2026-11-13): `nix flake check path:$PWD`, its eight checks.
