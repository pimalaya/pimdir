---
cairn: tasks
change: gtd-hardening
---

# Tasks

Track A of unfog cairn/changes/gtd-hardening.

- [x] migrations/storage/0001_init.sql: `supersessions`, cascading with both items, indexed on the superseding end
- [x] queries/storage/owner: `supersede_item`, `list_superseded_pending`; `rename_queue_targets` follows `supersedes.collection`
- [x] STORAGE §4.3, §14, §15.3: the superseding `add`, the table, the load; SYNC §5 and §11: the held tombstone, the `supersessions` store key
- [x] STORAGE §15.6: `x-vtodo`
- [x] STORAGE Annex A.4 wording
- [x] GUIDE §13 and §17: the drain of a superseding add; capture, move, the M1 rules
- [x] checks/invariants.sh: the pending supersession and its release, the cascades, the rename
- [x] vectors/sync 71 and 72, checks/vectors.py reading `supersessions`
- [x] vectors/gtd/writers.json and fixtures, checks/vectors.py validating their shape; vectors/README.md
- [x] queries/storage/read/list_replied.sql, STORAGE §14.1, GUIDE §14 and §17, an invariants scenario
- [x] `nix flake check path:$PWD`
- [ ] Log entry and landing: left to the user's review
