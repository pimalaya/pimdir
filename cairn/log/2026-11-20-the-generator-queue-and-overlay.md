---
cairn: log
change: the-freeze-plan
landed: 2026-11-20
---

# The generator's queue, drain, overlay and conflicts

The fourth code step of the generator of cairn/changes/the-freeze-plan (section 2). No part of the standard moves.

- **The queue** (generator/src/queue.rs): rows of every producer generator/scenarios.md lists, written through queue/ (`ensure_collection`, `pin_object`, `enqueue_action`, the id the connection answers held to the model's) and owner/ (`park_action`, `unconfirm_action`, `claim_action` then `record_receipt` for a row applied or an intent acknowledged), with the malformed and unknown store payloads of vectors/payloads.json.
- **The drain** (STORAGE §15.2, §15.3; SYNC §7): the model applies `add`, `set-flags` (its `base` as a change, parked over an unknown set), `remove` and `update` (parked on an `if_match` naming another body and on a conflict), `move` and `copy` (parked into another kind, into their own collection, a `move` on a conflict, for a placement holding no body), each into the receipt's `seq`; a pending create is a binding under the provisional handle with no base, as vectors/sync states one; intents and unknown rows are skipped.
- **The overlay** (STORAGE §15.4): `Model::overlay` folds a collection's pending rows as the drain applies them, a row the owner would park folding into nothing and an `update` restating the summary its body derives, the reading of the spec rather than of io-pimdir's reader, which shows rows the owner parks and keeps a folded update's summary stale (found by the spec lane, 2026-11-20).
- **Conflicts and refusals**: an item conflict, binding conflicts with a diverging body read and unread, a refusal standing on a pending create, written by `insert_item`, `insert_binding` and `refuse_binding`.
- **The oracle** adds `load_pending_actions`, `load_action`, `load_receipt`, `load_receipt_refusals`, `list_conflicted_items`, `list_conflicted_bindings`, `list_refusals` and `load_parked_actions`.
- **Checks**: two overlay tests state, from STORAGE §15.4, what a reader shows of the contacts and the inbox (an update chain folded with its summary, a stale update and one meeting a conflict folded into nothing, a remove hiding its item, an add shown, flags changed by their `base`, a `base` over an unknown set and a move queued on another collection not folded); a drained store is materialised and self-checked. Broken by hand to see each fail: a folded update keeping its old summary, the conflict gate removed, a parked row's attempt not counted, a receipt's refusals left out.
