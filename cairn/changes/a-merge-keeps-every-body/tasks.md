---
cairn: tasks
change: a-merge-keeps-every-body
---

# Tasks

- [x] STORAGE §15.3: `if_match` on the `update` payload, parked on mismatch, `v` unchanged; SYNC §7 `Edit` refused; vector 87
- [x] STORAGE §5, §6, §7, §10, §13, 0001_init.sql: `shared_object` counted and referenced, `bindings_by_shared_object`; recompute_refcounts.sql, collection_holds_objects.sql, release_bases_before.sql, new repair_shared_objects.sql, backfill_shared_object.sql comment; checks/invariants.sh (the pin, the release, the reconcile repair), failing on the statements before the change
- [x] SYNC §9: body-less upserts and conflicts move no `shared_object`; an item holding no body has changed; a fill; a divergence with an unread body recorded as `manual`; SYNC §6: the upgrade fetches it; vectors 80 to 84, 28 and 33 updated
- [x] SYNC §5, §9, STORAGE §11, §13: `prefer-*` and `PreferRemote` losers retained and reported `Overruled`; vectors 85, 86, 14 updated
- [x] SYNC §4: `SetFlags` as add and remove sets; vectors 02, 03, 09, 26, 27, 42 and checks/vectors.py's change key follow (algorithm-audit-2026-09-04 ledger :79)
- [x] SYNC §4: the unguarded push window stated
- [x] STORAGE §15.2, SYNC §7: an `add` or `update` with an unreadable body retried then parked (MUST), never applied; vector 88
- [x] SYNC §11 (vector fields `if_match`, `blob`, `failed`, `Overruled`), checks/names.sh
- [x] GUIDE §2, §10 to §13, OVERVIEW §6; log entry; lands in storage-draft-05 and sync-draft-05
- [x] `nix flake check path:$PWD`

Followers, tracked in their repositories: io-pimdir (mirror the migration and statements; count `shared_object` in its diff writer; src/hub.rs:467-494 per SYNC §9; the drain of a bodiless `add` and `update`; `if_match`; `SetFlags { add, remove }`; `Overruled`), neverest (drop the divergence workaround, driver.rs:3478-3866, once io-pimdir follows), every connector's `SetFlags`.
