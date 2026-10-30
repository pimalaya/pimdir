---
cairn: tasks
change: the-store-version-is-a-contract
---

# Tasks

- [x] STORAGE §4.2: version contract, major is the schema version, "recreated" replaced by reconciled
- [x] STORAGE §6: refuse above, reconcile only version 1 and first, migrations stamp both versions, no rebuild, every table preserved, reader and producer rule for an older store, draft reconcile-or-refuse
- [x] STORAGE §1: the Rebuildable bullet no longer points at §6's removed rebuild
- [x] STORAGE §4.3, §13, Annex A: `store_meta.derivation`, Annex A revision 1, re-derivation owed until recorded
- [x] migrations/storage/0001_init.sql: `derivation` column, header note
- [x] queries: set_store_version.sql, set_derivation.sql, init_store_meta.sql (`:derivation`), load_store_meta.sql (`derivation`)
- [x] checks/invariants.sh: init_store_meta stamps version 1 and the revision, set_store_version moves the version, set_derivation never lowers it, a store lacking `derivation` differs and is rebuilt with it at 1 (all failing on 8b2e8b6)
- [x] GUIDE §2, §3; README Status; OVERVIEW §1
- [x] `nix flake check path:$PWD`
- [x] Log entry (2026-10-30)
