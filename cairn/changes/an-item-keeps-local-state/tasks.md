---
cairn: tasks
change: an-item-keeps-local-state
---

- [x] Owner decisions (bounds, label folding), 2026-11-21, in proposal.md
- [x] STORAGE: the table (§4, migrations/storage), its life with the `seq` (§9, §11 purge and erase, §11.5), the `pimdir/` namespace, the readers' statements and the overlay (§15.4)
- [x] STORAGE §15, payloads/: the `set-property` action and its schema
- [x] SEARCH §8: `label:` and `property:`, their seeks, the grammar and the refusals
- [x] vectors: storage scenarios (purge, restore, rekey keep or drop it as stated), sync vectors proving no property derives a push, search cases for both fields
- [x] checks/invariants.sh scenarios, names, signatures, manifest restated; GUIDE and OVERVIEW §2; log entry (cairn/log/2026-11-21-an-item-keeps-local-state.md; no sync vector, an invariant and checks/names.sh instead, as the log says)

- [ ] io-pimdir follows (cairn/changes/as-fast-as-notmuch lists the implementation)
