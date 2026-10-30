---
cairn: change
id: ledger-housekeeping-2026-10-30
status: landed
created: 2026-10-30
---

# Ledger housekeeping before the STORAGE freeze

## Why

Edit 11 of the pimdir stable-release plan (2026-10-30). The README freeze gate asks for an audit ledger with no open item touching the schema, and the ledgers carry stale boxes, a landed change without its log entry and a change that belongs to another repository. An audit starts from these files (AGENTS.md §5), so a stale box costs every later reader.

## What

- algorithm-audit-2026-09-04: the missing log entry (landed, never logged); tick :76 (answered by STORAGE §4.3, a source id names one remote store-wide), :80 (decided never, the ladder closed instead) and :81 (dropped), each with its reason; :77 and :78 stay open as after-v1 migrations; :79 closes with a-merge-keeps-every-body.
- Stale boxes: created-at-stamped/tasks.md:21 (the canonical `store_meta` insert exists, `init_store_meta`); collection-role/tasks.md:18-20 (io-pimdir landed them, to check); cross-implementation-vectors/tasks.md:11 (meta.json is summaries.json); round-head/tasks.md:8 (the "not committed" header); orphan-blobs-are-swept-by-nobody's grace rule, superseded by the staging lock.
- audit-2026-10-10 :31: closed, the Android app bundles SQLite 3.49 (android/android/app/build.gradle.kts, requery's sqlite-android).
- pim-corpus: moved out of this repository.
- adopt-cairn: closed at the freeze, not before.

## Lands in

No part version: the ledger is not the text.
