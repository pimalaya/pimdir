---
cairn: tasks
change: a-refused-push-shows-on-its-receipt
---

# Tasks

- [x] The owner's answers to D1 to D5 of the proposal (2026-11-15, each as recommended)
- [x] SYNC §2, §4: the `Refused { reason }` outcome; §5: a refused change held by its key, the `Refused` event; §10: `RefusePlacement` and `ClearRefusal`; §11: the vectors' format 7; §12: the reason carries no credential
- [x] STORAGE §4.3, §13: the binding's `refusal`, `refused_key`, `refused_at`; §14: the ops; §14.1, §15.2, §15.4: receipts naming the item, the refused state, `prune_receipts` keeping a refused item's receipt; §18: the reason scrubbed
- [x] migrations/storage/0001_init.sql (edited in place while a draft), the `bindings_refused` index; no rehearsal, the change being no migration a release foresees
- [x] queries: `refuse_binding`, `clear_refusal`, `load_receipt_refusals`, `list_refusals`; `prune_receipts`; checks/names.sh, queries/signatures.json, checks/invariants.sh "refused: …" failing without them (2026-11-15)
- [x] vectors/sync/162 to 167: a refusal recorded, held (an add, a remove), an add edited since pushed, an update accepted clearing it, a withdrawal dropping it; checks/vectors.py's hold checks; vectors/manifest.json
- [x] GUIDE §9, §10, §13, OVERVIEW §5, §8
- [x] io-pimdir follows in its working tree (same id, 2026-11-15)
- [x] The draft-13 bump and tags, the owner's (pimdir 627271b, tagged with the io-pimdir pin, 2026-11-15)
- [ ] A refusal of a create the store offers a source, recorded nowhere today (log entry, "Left open")
- [ ] neverest and the Android app classify their refusals
