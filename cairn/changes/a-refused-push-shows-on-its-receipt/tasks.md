---
cairn: tasks
change: a-refused-push-shows-on-its-receipt
---

# Tasks

- [ ] The owner's answers to D1 to D5 of the proposal
- [ ] SYNC §2, §4: the `Refused { reason }` outcome; §5: a refused change held by its key, the `Refused` event; §10: `RefusePlacement`; §11: the vectors' format 7
- [ ] STORAGE §4.3, §13: the binding's `refusal`, `refused_key`, `refused_at`; §14: the op; §15.2, §15.4: receipts naming the item, the refused state, `prune_receipts` keeping a refused item's receipt; §18: the reason scrubbed
- [ ] migrations/storage/0001_init.sql (edited in place while a draft), checks/schema.sh, checks/floor.sh, checks/rehearsal/ if the change is foreseen as a migration
- [ ] queries: `refuse_binding`, `load_receipt_refusals`, `list_refusals`; `prune_receipts`; checks/names.sh, queries/signatures.json, checks/invariants.sh scenarios failing without them
- [ ] vectors/sync/: a create refused for good recorded and held, then pushed once edited; a refusal cleared by an accepted push; a withdrawal clearing it; checks/vectors.py
- [ ] GUIDE §9 to §12, OVERVIEW §5
- [ ] io-pimdir follows; neverest and the Android app classify their refusals
