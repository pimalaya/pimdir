---
cairn: tasks
change: every-vocabulary-is-open-or-closed
---

# Tasks

- [x] migrations/storage/0001_init.sql: kind `CHECK`, role without `CHECK`, level {1, 2}
- [x] queries/storage/owner/repair_levels.sql, repair_kinds.sql; STORAGE §6 repair step names them
- [x] STORAGE §4.3, §13 (closed and open, the list), §14 role paragraph
- [x] SYNC §3, §6 and GUIDE §3, §9, §11: no `0` left in the engine's reading
- [x] checks/invariants.sh: a fifth kind refused by `set_collection_kind` and over a declared kind, an undeclared kind accepted, a level 0 refused, conflict and support outside their sets refused, a role the vocabulary does not list recorded, the reconcile scenario rebuilding an earlier draft's closed role, open kind and 0 ladder only after `repair_levels` and `repair_kinds` (failing on 8b2e8b6)
- [x] vectors/sync/30 at level 1; checks/vectors.py kinds and levels (failing on vector 30 before its edit)
- [x] no-custom-kinds: its `CHECK` and scenario ticked there
- [x] Edit 9 recorded as dropped (Android stores are `sha256-128`)
- [x] `nix flake check path:$PWD`
- [x] Log entry (2026-10-30)
