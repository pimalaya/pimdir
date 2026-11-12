---
cairn: tasks
change: a-delivered-create-waits-for-its-arrival
---

# Tasks

- [x] SYNC §2 the term; §3 no origin under a provisional handle; §4 an accepted relocation and a handle-less add deliver; §5 a delivered create waits, never absent nor dropped, its tombstone held; §6 it lands, a tombstone keeping its destination, no upgrade fetching a provisional handle; §7 `Remove` and `Move` on it; §8 the rekey; §10 the op
- [x] STORAGE §2 the term, §9's table (a delivered create, live or tombstoned, lands; a provisional binding is no "other handle"), §10 the absence, §14 the origin and `DeliverPlacement`
- [x] queries/storage/owner/deliver_binding.sql (new); list_unstamped_bindings.sql and origin_for_link.sql leave out provisional handles; destination_for_link.sql names a delivered create too (review, 2026-11-11)
- [x] checks/invariants.sh: "A delivered create is no member a listing names", failing on the old statements (origin and absence)
- [x] vectors/sync/ 20, 48 and 92 deliver their create; 136 to 139 new; checks/vectors.py: a provisional binding may hold a base naming nothing, a delivered create is never absent nor counted, a Remove is pushed against the handle landing a delivered tombstone; vectors/README.md; vectors/manifest.json restated
- [x] Review 2026-11-11: no re-pend on a closing round (vector 139 keeps both waiting), report while waiting, early delivery MAY, a delete leaves one collection (SYNC §4), the destination derived at landing, the terms of §2 and §5 aligned
- [x] GUIDE §9 to §12 follow
- [x] `nix flake check path:$PWD` green on the working tree, its seven checks (2026-11-11)
- [x] `nix flake check` on the tracked files green at commit (2026-11-12); checks/tags.sh: sync-draft-09 has no tag yet, the tag being the owner's to make
- [x] checks/io-pimdir.rev to the io-pimdir commit following it (branch delivered-create): 3a51ae7
- [x] sync-draft-09 (the owner, 2026-11-12): SYNC Status, §10 and §12, STORAGE §14 and §17 examples, README, AGENTS.md, invariants; storage-draft-09 unchanged, no migration moving
- [x] An outcome states whether a relocating `Remove` relocated (SYNC §2, §4, §11): vectors to format 4, 20, 48 and 137 state it, 140 a delete delivering nothing; checks/vectors.py requires it
- [ ] collect_before (STORAGE §11.3) may collect a live delivered create holding a body, its staged flags lost once its arrival is named afresh: open, low
