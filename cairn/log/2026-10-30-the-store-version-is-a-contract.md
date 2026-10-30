---
cairn: log
change: the-store-version-is-a-contract
date: 2026-10-30
---

# The store version is a contract

Edit 1 of the pimdir stable-release plan. Before it, an implementation meeting a newer store MAY rebuild it and lose un-pushed edits, reconciliation dropped what a newer owner added (reproduced through himalaya at io-pimdir 3b4bed8: `supersessions` and four `task_summary` columns gone), the documents said both "recreated" and "reconcile or refuse", and nothing canonical moved `store_meta.version`.

- **STORAGE §4.2** (normative): `user_version` and `store_meta.version` move together, only in a migration's transaction; the part's major is the schema version; 0001_init.sql never changes once released. Guarded by checks/invariants.sh ("version: a migration's stamp moves store_meta.version").
- **STORAGE §6** (normative): the owner's open refuses a store above its version (every profile, never reconciled, migrated, rebuilt nor written), reconciles only a version 1 store, against 0001_init.sql alone and before any migration, then runs each migration with `set_store_version`. "MAY rebuild" is gone; a migration preserves every row of every table; a reader or producer reads an older or unreconciled store with missing columns `NULL` and missing tables empty; while draft an owner reconciles or refuses, never recreates. The refusal and the ordering are an implementation's behaviour, which no check here runs; io-pimdir carries the synthetic 0002 test.
- **STORAGE §6, §13, Annex A** (normative): Annex A is at revision 1; `store_meta.derivation` (new column, default 1, so reconciliation adds it to every existing store) records the revision a store was derived under; `init_store_meta` binds `:derivation`, `load_store_meta` answers it last; an owner at a later revision re-derives and records it with `set_derivation`, which never lowers it. Guarded by checks/invariants.sh ("version: init_store_meta stamps ...", "derivation: ... never lowers it", the reconcile scenario rebuilding a `store_meta` without the column).
- **GUIDE §2, §3, README Status, OVERVIEW §1** (informative) follow.

Each new scenario was run against 8b2e8b6 and failed there. io-pimdir vendors migrations/ and queries/ byte for byte and follows in its own cairn. `nix flake check path:$PWD` passes.
