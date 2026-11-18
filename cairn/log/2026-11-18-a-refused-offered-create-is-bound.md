---
cairn: log
change: the-draft-14-lines
date: 2026-11-18
---

# A refused offered create is bound

The line left open by cairn/log/2026-11-15-a-refused-push-shows-on-its-receipt.md, seen live by neverest on 2026-11-16: a create the store offers a source binding nothing of the item (SYNC §3, §9), refused for good, had no binding for `RefusePlacement` to stand on, so `refuse_binding` recorded nothing and the next run pushed the same `Add` again, refused and reported every run, invisible to `load_receipt_refusals` and `list_refusals`. Proposal with its alternatives and decision D6: cairn/changes/the-draft-14-lines/proposal.md, "The refusal of a create a source binds nothing of". Specified as recommended, (a), for the owner to confirm or turn back before the draft-14 bump.

## Rules and their checks

- **Bound on its refusal** (SYNC §5, §10, STORAGE §14, GUIDE §10 step 7): the write recording the refusal of an offered create upserts it as the source's own pending create, under the provisional handle it was pushed under, no base, before the `RefusePlacement`, so the refusal stands on a binding. From then every rule of a pending create applies as written: held by its key, reported every run, read by the receipt and `list_refusals`, pushed again once its key changes, landed by a listing, withdrawn by a `Remove` or the item's delete. No schema, statement or op change; refuse_binding.sql's comment follows.
- Vector 171 (a refused offered create bound with its refusal, the other source's binding untouched), failing on io-pimdir d6ca71a ("bindings rows differ") and passing with a one-line prototype of the upsert in a scratch copy, io-pimdir's suite run whole there. checks/vectors.py now holds that every `Refused` outcome stands on a binding of the run's source after the run, an offered one as a pending create, and requires a case of it ("sync: a case holds an offered create bound on its refusal" before vector 171).
- vectors/manifest.json restated; `checks/vectors.py .` green (171 sync cases).

## Left open

- A person wanting the item on every source but the refusing one has no action for it: a `Remove` deletes it everywhere, as for a bound create. A per-source withdrawal is a later question (proposal, "What (a) does not give").
