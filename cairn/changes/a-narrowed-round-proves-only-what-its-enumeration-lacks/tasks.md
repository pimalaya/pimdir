---
cairn: tasks
change: a-narrowed-round-proves-only-what-its-enumeration-lacks
---

# Tasks

- [x] SYNC §5: a narrowed round finds absent only what its enumeration lacks, whatever the date; one handing none finds nothing absent and reports what it left unlisted; the filter's two misses named; `enumerated` asked on a band round's last page too; the margin no longer "a superset of the scope"; the list of what is no absence
- [x] queries/storage/owner/list_unstamped_bindings.sql: `:narrowed = 0 OR (:enumerated = 1 AND handle missing)`, its comment; parameters and columns unchanged (queries/signatures.json unmoved by it)
- [x] STORAGE §10 round bullet, GUIDE §9 to §11 (the last page, the connectors' narrowing), OVERVIEW §5
- [x] checks/invariants.sh "A narrowed listing proves only what its enumeration lacks": none absent without an enumeration, a member the enumeration holds kept though dated before the round opened, a band whose upper bound read the arrival keeping an old-dated member; three of them fail on the old statement (2026-11-15)
- [x] checks/vectors.py: `provable` reads the enumeration alone; two rule cases required (a dated member kept with an enumeration holding it, and with none); fails on the old vector 107 and on the tree lacking 160 (2026-11-15)
- [x] vectors/sync/107 rewritten (14 kept), 160 (a band narrowed by arrival keeps an old-dated member its enumeration holds) and 161 (a `Date` ahead of its arrival kept) new, 47's note; vectors/README.md; vectors/manifest.json restated
- [x] `nix flake check path:$PWD` green on the working tree, its nine checks (2026-11-15)
- [x] io-pimdir follows in its working tree: re-vendored spec, the engine applying the page's proof itself; 107, 160 and 161 fail there on the old statement and pass on the new (2026-11-15)
- [ ] The owner's decision: reading (a), (b) or (c) of the proposal; (a) is what the tree holds
- [ ] The bump and tags (the owner's): sync-draft-12 and storage-draft-12, checks/tags.sh failing until then
- [x] Commit both repositories, then checks/io-pimdir.rev to the io-pimdir commit following it (pimdir 6ccc3d4, io-pimdir 3b6eaa9, pinned at 11145ef)
- [ ] Consumers: neverest hands `enumerated` on a band round's last page (its IMAP and Gmail connectors leave it out there), or accepts that its narrowed band rounds infer no delete; the Android app and neverest take the io-pimdir release carrying the statement
