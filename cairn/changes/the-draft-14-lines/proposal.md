---
cairn: change
id: the-draft-14-lines
status: in-progress
created: 2026-11-18
---

# The draft-14 lines

## Why

The lines left for the next draft before pimdir v1, gathered so they land in one bump: the owner ruling D34 on refusals (2026-11-16, cairn/changes/a-refused-push-shows-on-its-receipt/tasks.md), the format parts of the CLI family analysis of 2026-11-15 (PIM-12, PIM-14), the create a source binding nothing of refuses (seen live by neverest, 2026-11-16), and the audit-2026-11-12 lines C1, C2 and C4 marked "before".

## What changes

1. SYNC §4: `401`, `407` and `423` are no refusal, beside `408`, `409`, `412`, `425` and `429`; a quota exceeded is no refusal, a size exceeded stays one. Each is left unreported, as a transport failure is: a change held by its key would never be pushed once the credential is renewed, the lock released or space freed (D34).
2. SYNC §3, §5, §9, STORAGE §10: a deleted item a source binds projects `Tombstone` whatever conflict stands, carrying its binding's divergence; a binding's conflict names a server edit that beats the delete, so such a tombstone derives no `Remove`; an item conflict holds no delete back and is kept by the retained item (PIM-12, as io-pimdir's hub already projects).
3. SYNC §7, STORAGE §15.2 to §15.4: a `Move` into the collection its placement is in is refused, a queued `move` there parked naming it and never enqueued (PIM-14, io-pimdir's `move-in-place`).
4. The refusal of a create offered to a source binding nothing of it: bound as its pending create on its refusal (below, D6).
5. C1, C2, C4 of audit-2026-11-12 (unit 3).
6. The bump to storage-, sync- and search-draft-14 (unit 4).

## The refusal of a create a source binds nothing of

Seen live by neverest on 2026-11-16, left open by cairn/log/2026-11-15-a-refused-push-shows-on-its-receipt.md. A create the store offers a source (§3: the source binds nothing of an item another source holds, the store holding its body, §9) is pushed as an `Add` under the provisional handle its key derives. When the remote refuses it for good, `RefusePlacement` names a handle no binding holds, `refuse_binding` updates nothing, and the next run pushes the same `Add` again: refused and reported every run, never held, and invisible to `load_receipt_refusals` and `list_refusals`, which read bindings. That is the per-run memory the sync data-loss lessons warn of, on the exact case (a Graph folder, a floating time) the refusal was made for, as soon as two sources sync one collection.

### Alternatives

- **(a) Bind it on its refusal (recommended).** The write recording the refusal first upserts the offered create as this source's own pending create (a binding under the provisional handle, no base, the item's flags and body), then records the refusal on it. Nothing new in the schema, the statements or the ops: an offered create is already what an accepted `Add` turns into a binding, and a refused one stops half way. From then on every rule of a pending create applies as written: held by its key, reported every run, read by the receipt of the row that queued the item and by `list_refusals`, pushed again once its key changes (a body edited, the flags changed), landed by a listing naming its member (§6), and gone with the item's delete (a tombstone with no base is withdrawn, §3) or a `Remove`. Cost: one engine rule (SYNC §5), the op's wording (STORAGE §14), a vector and a check.
- **(b) A table of refusals keyed by item and source**, for offered creates only, or for every refusal. Reopens D2 (binding columns, decided 2026-11-15): two homes for one fact, or a migration of the one just landed, and every reader learning a second join.
- **(c) Never offer it again**: a refused offered create is excluded from the projection for that source. Loses the rule that a change derived since is asked again, and needs a column of its own all the same, to remember the exclusion.
- **(d) Status quo, stated**: pushed and reported every run, the run's report the only trace. The per-run memory the refusal change was made to remove, and no receipt shows it.

### What (a) does not give

A person wanting the item on every source but the refusing one has no action for that: a `Remove` deletes the item everywhere, as for a bound create today. A per-source withdrawal (an `Abandon` widened to a refused create, or a source-scoped `remove`) is a later question, not a reason to pick another shape.

### Decision asked

- **D6** Bind a refused offered create as the source's pending create (a, recommended), a table (b), exclusion (c) or the status quo (d). Specified as (a) in the working tree, for the owner to confirm or turn back before the draft-14 bump.
