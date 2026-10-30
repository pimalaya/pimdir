---
cairn: log
change: ledger-housekeeping-2026-10-30
date: 2026-10-30
---

# Ledger housekeeping before the STORAGE freeze

Edit 11 of the pimdir stable-release plan. The README freeze gate reads the audit ledgers, and an audit starts from them (AGENTS.md §5), so stale boxes cost every later reader.

- **algorithm-audit-2026-09-04**: its missing log entry written (2026-10-30-algorithm-audit-2026-09-04.md); :76, :80, :81 ticked with their reasons, :77 and :78 left open as after-v1 migrations, :82 and :83 open and touching no schema.
- **Stale boxes settled**: created-at-stamped :21 (`init_store_meta` exists), collection-role :18-20 (checked in io-pimdir: `set_collection_role`, the reader's `role`, tests/collection_role.rs), cross-implementation-vectors :11 (meta.json became summaries.json), round-head :8 (committed since).
- **orphan-blobs-are-swept-by-nobody**: its grace rule is superseded by the staging lock, recorded in a new entry of that change.
- **audit-2026-10-10 :31**: closed, the Android app bundles SQLite 3.49.0 (requery's sqlite-android, android/android/app/build.gradle.kts:190).
- **adopt-cairn**: left open until the freeze, as decided.
- **pim-corpus**: not moved. It goes to the corpus's own repository, which does not exist yet, its name (`io-pim-corpus` or `pim-corpus`) still open in its proposal. The move is the user's: create that repository, copy cairn/changes/pim-corpus/proposal.md and tasks.md into its cairn/changes/ (its first change, its "Where pimdir comes in" kept), then delete cairn/changes/pim-corpus/ here with a log entry naming the destination.

No text of a part changes. The open items left with a schema touch: none (the purge log and the pending bit are post-v1 migrations by decision).
