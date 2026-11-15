---
cairn: change
id: a-refused-push-shows-on-its-receipt
status: draft
created: 2026-11-15
---

# A refused push shows on its receipt

## Why

Found by the live campaign of 2026-11-15, reported by the session owning neverest. A frontend queues a write, the drain applies it, and every sync then has the remote refuse the push for good: a message appended to a Graph folder other than Drafts, an event at a floating time the Google Calendar API refuses. The producer following its row reads it `applied` (`load_receipt`, STORAGE §15.4), and the refusal shows only in that run's report, unlinked to the row and without its reason. The user is never told, and nothing they can read says what to do.

What the parts say today:

- STORAGE §15.2: an action is applied and its row deleted in one transaction, which records its receipt (`id`, `collection`, and for an `add` the `seq` of the item it created). The queue's states are pending, parked and gone; a receipt says applied. Nothing after the drain touches the receipt.
- SYNC §2, §4: an outcome is `Accepted` or `Rejected`, which carries nothing. io-pimdir's `PimdirPushOutcome::Rejected` is documented as optimistic concurrency, "the base was stale", so a refusal for good has no outcome of its own either.
- SYNC §5: "`Rejected` or unreported leaves it pending, and an engine SHOULD report a create rejected on consecutive runs rather than push it for ever". A report a run forgets is the per-run check the sync data-loss lessons warn of: the refusal belongs in the store.

So the gap is three missing facts, none a defect of a single rule: an outcome stating a refusal for good with its reason, a place in the store that keeps it, and a read linking it to the row that queued the change.

## The ask, and why not as asked

The ask was to turn the originating row back into its parked state, with the reason. That is the wrong shape:

- The row's effect is in the store: the `add` created the item, the `update` stored the body. A parked row is one not applied (§15.2); `retry_action` would apply it again (an `add` then parks as a live duplicate), and `cancel_action` would withdraw the row and leave the item, the very thing the user means to get rid of.
- One push is not one row: a create, then a flag change and an edit queued on it, are pushed as one `Add`; and one row is pushed to every source syncing the collection, one refusing while another accepts. A row's state cannot say which source refused which change.
- The receipt is already the record of an applied row, and the store already holds the push state per item and source, the binding.

## Recommendation (not implemented, the owner's to decide)

1. **An outcome for a refusal** (SYNC §2, §4): `Refused { reason }`, the remote refusing the change itself as it stands (an HTTP 4xx naming the request, 408, 409, 412, 425 and 429 aside: Graph's "append to Drafts only", a floating time refused, a size or quota limit, a folder the account may not write). `Rejected` stays a precondition the base failed (a stale `If-Match`), retried after the next listing; a transport failure stays unreported. `reason` is the server's text, through STORAGE §18's scrub. A connector that cannot tell answers `Rejected`.
2. **The binding keeps it** (STORAGE §4.3, §13): `bindings.refusal` (the reason), `refused_key` (the idempotency key of the change refused, SYNC §4) and `refused_at` (stamped by SQLite); a new op `RefusePlacement { collection, handle, key, reason }` and owner statement `refuse_binding`. Cleared in the write that records the binding's next accepted push, and gone with the binding (a withdrawal, a landing).
3. **A refused change is held, not hammered** (SYNC §5): the engine derives the change as before, and pushes it only when its key differs from `refused_key`, so a change the user made since (a body edited, a flag changed, a move into Drafts) is pushed, and the same one is not, run after run. It stays pending: nothing is dropped. The run reports a `Refused` event for each refusal it holds or records, naming the handle, the source and the reason, which replaces the SHOULD on consecutive runs.
4. **The receipt reads it** (STORAGE §15.2, §15.4): a receipt names the item for every action on one (`seq` for a `set-flags`, `update`, `remove`, `copy` and `move` too, the created item for a `move` and a `copy`), and a new reader statement `load_receipt_refusals(id)` answers, per source, the refusal standing on that item's binding (`source`, `refusal`, `refused_at`). `load_receipt` keeps its columns. A producer then shows a row as applied and refused by a source, with the reason: a fourth state beside pending, parked and gone. `prune_receipts` keeps a receipt while a refusal stands on its item.
5. **The way out is the item's own actions**, never the row's: a `remove` withdraws a refused create, which a-pending-create-is-withdrawn-whatever-the-rights lets through whatever the source's delete right; a `move` into a collection the source accepts (Drafts) or an `update` is a new change, pushed. A reader lists every refusal of a collection (`list_refusals(collection)`) for a frontend's queue view.

## Decisions asked

- **D1** The outcome: a new `Refused { reason }` (recommended), or a reason and a `permanent` flag on `Rejected`.
- **D2** Where it is kept: binding columns (recommended: the binding is the push state of an item on one source, and drops with it), or a table of refusals keyed by item and source.
- **D3** Hold by key (recommended), or push again every run as today, recording only.
- **D4** Receipts naming the item for every action (recommended), or for an `add` alone, refusals of other actions then shown by collection only.
- **D5** Re-parking the row as asked: not recommended (above).

## Cost

A schema change (three binding columns), three statements (`refuse_binding`, `load_receipt_refusals`, `list_refusals`) and two changed (`record_receipt`'s callers binding `seq` more often, `prune_receipts`), a write op, a seam outcome, a sync event, and the sync vectors' format moving to 7 (an outcome `Refused` with its `reason`, a binding's `refusal` and `refused_key`, the event). Both parts move a draft: storage-draft-12 and sync-draft-12, which a-narrowed-round-proves-only-what-its-enumeration-lacks bumps already. io-pimdir follows (its cairn/changes/a-refused-push-shows-on-its-receipt), then each connector classifies its refusals: neverest and the Android app. Nothing of it is written yet: the shape needs the owner's answers first.
