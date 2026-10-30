---
cairn: log
change: every-vocabulary-is-open-or-closed
date: 2026-10-30
---

# Every vocabulary is open or closed

Edit 6 of the pimdir stable-release plan. A `CHECK` change is a rebuild and, once released, a new schema version, so each vocabulary is now decided.

- **STORAGE §13** (normative): what closed (a `CHECK`, grown by a version) and open (no constraint, an unknown value read as the column says) mean, and the list. Closed: `kind`, `level`, `deleted`, `conflicted`, `conflict`, `support`, `origin`, `item_reference.role`. Open: `collections.role`, `action`, `capability`.
- **migrations/storage/0001_init.sql**: `collections.kind` gains its `CHECK` (no-custom-kinds); `collections.role` loses its `CHECK`, the role vocabulary following a registry that grows; `items.level` is `CHECK (level IN (1, 2))`. Guarded by checks/invariants.sh: a fifth kind refused, also over a declared kind, an undeclared kind accepted, a level 0 refused, a role the vocabulary does not list recorded, conflict and support outside their sets refused.
- **STORAGE §6** (normative): reconciliation repairs before rebuilding, `repair_levels` (0 to 1) and `repair_kinds` (another media type to `''`). Guarded by the reconcile scenario: an earlier draft's shape (closed role, open kind, a ladder taking 0, a row at 0, a `text/x-vlist` collection) fails its `items` rebuild on the `CHECK` until repaired, then rebuilds with nothing differing.
- **STORAGE §14** (normative): the role vocabulary is open; a reader reads a role it does not know, or another kind's, as none.
- **SYNC §3, §6, GUIDE §3, §9, §11**: the `0` reading leaves the engine.
- **vectors/sync/30**: its starting row is at `level` 1, not an earlier draft's 0. checks/vectors.py now checks every vector kind is of the set and every level of the ladder; it failed on vector 30 before the edit.
- Edit 9 (BLAKE3 alone) is dropped: the Android app creates its stores with `hash_algo` `sha256-128` (PimdirHash.java:16, PimdirDb.java:143), so `store_meta.hash_algo` keeps both values.

Each new scenario failed against 8b2e8b6. io-pimdir vendors the schema and the statements and follows. `nix flake check path:$PWD` passes.
