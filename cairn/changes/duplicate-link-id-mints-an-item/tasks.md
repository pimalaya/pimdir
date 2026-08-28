---
cairn: tasks
change: duplicate-link-id-mints-an-item
---

# Tasks

## SPEC.md

- [x] §9: define `link_id` as the store's key, state the three-branch minting rule, and state the `dup:<hint>#<handle>` form. The glossary entry ("link id: the item's stable cross-collection identity (`Message-ID`, vCard/iCal `UID`)") becomes the definition of the **hint**, with the key defined beside it.
- [x] §9: restate the dedup and merge sentence so the asymmetry stays explicit: dedup keys on hash, matching keys on the hint, the key is neither.
- [x] §9.1: state that a minted item draws its own `seq`, and that the bare-hint copy keeps the store-global one, so the cross-collection guarantee is unchanged.
- [x] §9.2: check the account-scoping paragraph still reads correctly now that two items in one collection may share a hint (it argues about two accounts minting one `UID`; the same argument now has a within-account case).
- [x] §10: remove `ambiguous_handles` and the freeze prose; restate the never-repoint rule as a refusal, keeping §12's rebuild as the one licensed rebind.
- [x] §12: the per-handle licence paragraph keeps its shape, with "records the incoming handle as ambiguous" replaced by "refuses the write".
- [x] §13: drop `ambiguous_handles` from the `bindings` column list.
- [x] §14: `update_binding`'s stated behaviour on a handle change; drop any ambiguity wording from the `check` description.
- [x] §15.3: keep the queued `add` parking on a duplicate `link_id`, and say why the two answers differ: minting is what reading a server's collection requires, parking is what authoring an item locally requires. The store is liberal in what it accepts from a source and strict in what a producer may create.
- [x] Annex A.1, A.2, A.3: name what each kind's **hint** is, and state that Annex A derives the hint while §9 assigns the key. A.3 loses the sentence resting on CalDAV's enforcement of uniqueness and states the opposite: the format does not assume the server enforced it.
- [x] Annex A.3: keep the recurrence-set rule as it stands (one resource per `UID` on the wire is unaffected).

## Canonical SQL

- [x] migrations/: `bindings.ambiguous_handles` removed from the canonical schema, version 1 still edited in place.
- [x] queries/: `update_binding`, `insert_binding`, `load_bindings` and any statement naming the column.
- [x] Check no statement keys on `link_id` in a way that assumed it equals the hint.

## Vectors

- [x] vectors/: a case per kind where the hint is already claimed, giving the minted key, so an implementation cannot mint a different one.
- [x] vectors/: the two existing fallback cases (`alt:`, `hash:`) stay as they are, since minting is a third trigger and not a replacement.

## Landing

- [ ] io-pimdir's spec-fidelity suite green against this checkout (it is the only place the canonical SQL is ever loaded). Red by construction until io-pimdir lands its own delta, this repository leading the chain: the suite reports exactly one difference, its inlined `bindings` still carrying `ambiguous_handles`, and its three statement tests pass.
- [x] `cairn/log/2026-08-28-duplicate-link-id-mints-an-item.md`, naming `duplicate-link-id-freeze` as superseded and pointing at the Posteo evidence.
- [x] Mark this change `landed`.
