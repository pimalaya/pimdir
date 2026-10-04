---
cairn: log
change: acknowledged-intents-leave-receipts
date: 2026-10-04
---

# An acknowledged intent leaves a receipt

Receipts (2026-10-04, collection-create-occurrences-receipts) told a producer what an applied row became, but an intent is never applied by the drain: its performer carries it out and acknowledges it with `cancel_action`, which recorded nothing. A message sent or a collection created then read exactly like a row withdrawn by request, both gone from the queue and the receipts, so a producer (himalaya, then MOA) could not tell a send from a cancellation.

- **§15.5.** A performer acknowledging an intent it performed MUST call `record_receipt` in the transaction of its `cancel_action`: the intent's `id`, its collection and, as `seq`, the item its effect left in the store when the performer knows it, `NULL` otherwise. Replacing an intent by its store change records the intent's receipt with a `NULL` `seq`; the change is a row of its own. A withdrawal records none. Guarded by checks/invariants.sh ("acknowledge:", three scenarios).
- **§15.4.** A performed intent leaves a receipt; only a row withdrawn by request, or one whose receipt was pruned, is found nowhere.
- **§4.3, §13, Annex B.2.** `receipts` and its `seq` cover performed intents; intents are acknowledged with `cancel_action` and their receipt.
- **queries.** Comments of `record_receipt`, `cancel_action` and `load_receipt`; no statement changed shape. GUIDE.md's follow and acknowledge procedures follow.

Decided: the receipt is written by the existing `record_receipt` beside `cancel_action` rather than by a new statement, so the queue keeps one way to remove a row and one to record what it became; the collection is the row's own, which the performer read with the intent.

Normative edits under `draft-04`, not yet tagged, so the draft number stays.
