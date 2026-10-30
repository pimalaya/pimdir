---
cairn: tasks
change: absence-deletes-only-from-a-complete-round
---

# Tasks

- [x] SYNC §5 (:147 against :192, :270): which absences count, and that they propagate; a `Remove` from a tombstone the store holds
- [x] SYNC §4 (:87) and §5 (:143, :155): MUST on `complete`, `last` and the cursor; the engine refuses a non-last page without a cursor; a round reconciles its scope alone
- [x] SYNC §5: the mass-absence guard (more than 50% of a scope of at least 20 bound members parks and reports), resumed from the first page, closed by `accept_absences`
- [x] SYNC §5: a server collection deleted from an absence only when enabled, and then only empty or fully reconciled in the run
- [x] vectors/sync: 74 (two-source partial round), 75 and 76 (a closed round's absence propagates and is pushed), 77 and 78 (the park and its confirmation), 79 (a page without a cursor fails the run)
- [x] checks/vectors.py: the prose rule (a based binding of the run's source leaves only for a stated removal, a tombstone, a rekey or an absence from a round the run closed, in scope and not parked; a mass absence parks), beside the Remove check it extends; fails on 74, 77 and 79 broken as the rule forbids, where the old check caught only 79's shape
- [x] SYNC §11 (vector fields `accept_absences`, `parked`, `failed`), checks/names.sh
- [x] GUIDE §10, OVERVIEW §5 and §6; log entry; lands in sync-draft-05
- [x] `nix flake check path:$PWD`

Not checkable here, stated for the followers: the server-collection rule has no vector format (vectors run one collection), so it binds by its text alone. Followers, tracked in their repositories: io-pimdir (src/sync.rs:572-577, rekey.rs:499, rekey `complete`, the park and `accept_absences`), neverest (UIDVALIDITY, DAV truncation, `collection.delete` default false).
