---
cairn: log
change: a-refused-push-shows-on-its-receipt
date: 2026-11-15
---

# A refused push shows on its receipt

Found by the live campaign of 2026-11-15, reported by the session owning neverest: a push the remote refuses for good (an append into a Graph folder other than Drafts, a floating time Google Calendar refuses) left the row that caused it `applied`, the refusal shown only in that run's report, unlinked to the row and without its reason, and pushed again every run. Proposal, decided by the owner on 2026-11-15 as recommended (D1 to D5): cairn/changes/a-refused-push-shows-on-its-receipt. Version names untouched: storage-draft-12 and sync-draft-12 move with the owner's draft-13 bump.

## Rules and their checks

- **An outcome for a refusal** (SYNC §2, §4): `Refused { reason }`, the remote refusing the change itself as it stands; `Rejected` stays a precondition the base failed, and is what a connector that cannot tell answers; a transport failure is no outcome. Vector 162 (an add refused, its refusal recorded and reported), failing on io-pimdir before its change: no `Refused` event.
- **The binding keeps it** (STORAGE §4.3, §13, §14, SYNC §10): `bindings.refusal`, `refused_key`, `refused_at`, all three or none by `CHECK`, the key held to sixteen lowercase hexadecimal digits; `RefusePlacement` (`refuse_binding`) records one, `ClearRefusal` (`clear_refusal`) clears one in the write recording the binding's next accepted push, both after the batch's upserts and drops; a drop of the handle takes it, a `Superseded` or `Rekeyed` one included; `bindings_refused` holds the refused bindings. checks/invariants.sh "refused: …" (ten expectations), failing on the old schema with "no such column: b.refusal".
- **A refused change is held** (SYNC §5): a change derived under the key a refusal standing on its binding names is not pushed, stays pending and is reported `Refused` every run; one derived under another key is pushed; the SHOULD on creates rejected on consecutive runs is gone. Vectors 163 (an add held) and 166 (a remove held), failing on io-pimdir before its change: the same `Add` and the same `Remove` pushed again; 164 (an add edited since, pushed and landed under another key); 165 (an update under another key, accepted, clearing the refusal), failing on io-pimdir before its change: the refusal stood; 167 (a withdrawal taking the refusal with its binding). checks/vectors.py holds that no push carries a refused key, that a `Refused` outcome stands on its binding under the pushed key and is reported, that a held refusal is reported and stands, and that an accepted push clears it, and requires a case of each; each of its three new checks failed on a vector altered to break it (162 without the refusal, 163 pushing, 165 keeping the refusal).
- **A create the source binds not** (SYNC §5): one the store offers it has no binding to record a refusal on, and is pushed again by the next run. Stated, not changed: see "Left open".
- **The receipt names its item and reads the refusal** (STORAGE §15.2, §15.4): `record_receipt` binds the `seq` of the item every action on one acted on (the item a `set-flags`, an `update` or a `remove` names, when the store holds it; the one a `move` or a `copy` left in its target), its text unchanged; `load_receipt_refusals(id)` answers per collection and source the refusals standing on every row of the receipt's `seq` in the account of its collection, so a move reads its target's create; `list_refusals(collection)`; `load_receipt` keeps its columns; `prune_receipts` keeps a receipt while a refusal stands on its item. checks/invariants.sh "refused: pruning keeps a receipt while a refusal stands on its item", failing on the old `prune_receipts` ("expected [1 3], got []"); the account boundary and the move's target read by "refused: a receipt keeps its columns …" and "refused: a move's receipt …".
- **The reason is scrubbed** (STORAGE §18, SYNC §12): `bindings.refusal` joins the columns no credential reaches, a connector's reason included.
- **The vectors' format moves to 7** (SYNC §11, vectors/README.md): the outcome `Refused` and the event `Refused` with their `reason`, a binding's `refusal` and `refused_key`, `refused_at` excluded as a SQLite instant; every sync case restated at 7.
- queries/signatures.json and vectors/manifest.json restated; GUIDE §9, §10, §13 and OVERVIEW §5, §8 follow. Checked on the working tree (2026-11-15): `nix flake check path:$PWD` green, 167 sync cases, 263 of 263 statements run. checks/tags.sh fails until the owner bumps the drafts.

## Left open

- A refusal of a create the store offers a source (propagated from another source, SYNC §3, §9) is recorded nowhere, the source binding nothing: it is pushed and reported every run. Binding such a create on its refusal would make it this source's own pending create, a shape for the owner to decide.
- A refusal stamps nothing in the change feed (§4.5): a reader learns of one by reading the receipt or `list_refusals`, not from `list_items_changed_since`.

## Consumers

io-pimdir follows in its working tree (its log of 2026-11-15, same id): the outcome, the ops, the hold, the event, the receipt reads. neverest and the Android app classify their connectors' refusals next, answering `Refused` where the remote names the request.
