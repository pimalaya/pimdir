---
cairn: tasks
change: a-pending-create-is-withdrawn-whatever-the-rights
---

# Tasks

- [x] queries/storage/read/load_item_capabilities.sql answers `held`, its comment; queries/signatures.json restated
- [x] STORAGE §15.6, the sources concerned: a source answering `held` 0 left out for a `remove`, a `move` or a `copy`, met in the target alone; the target's sources asked an `add`'s capabilities; §14.1 names the column
- [x] GUIDE §12, the producer's gate
- [x] checks/invariants.sh "capability: …": a held binding answers 1, a pending create 0, a delivered create 1; both fail on the old statement (2026-11-15)
- [x] `nix flake check path:$PWD` green on the working tree (2026-11-15)
- [x] io-pimdir follows in its working tree: the gate reads `held` for a remove, a move and a copy; its test fails on the old gate with "mail.message.remove … pull-only" (2026-11-15)
- [ ] The bump and tags (the owner's), with a-narrowed-round-proves-only-what-its-enumeration-lacks
- [x] Commit both repositories, then checks/io-pimdir.rev to the io-pimdir commit following it (pimdir 9ce9c3d, io-pimdir d7273d3, pinned at 11145ef)
- [ ] calendula reads `PimdirReader::item_capabilities`, which still lists every source binding the item: a UI greying out a delete from it greys out a withdrawal; to look at when it next moves
