---
cairn: log
change: the-freeze-plan
landed: 2026-11-20
---

# The generator's overlay: arrivals and pending creates apart

The generator's side of the overlay rules STORAGE §15.4 now states (G4 and G5, cairn/log/2026-11-20-what-an-overlay-shows.md), plan 2's "The oracle" of cairn/changes/the-freeze-plan. No part of the standard moves.

- **Pending creates apart** (generator/src/queue.rs, STORAGE §9.1, §15.4): `Model::overlay` no longer folds a collection's pending `add` rows into its items, the `seq` of what each creates being the owner's to draw; `Model::pending_creates` lists those rows apart, as io-pimdir's `pending_creates` does.
- **Arrivals** (STORAGE §15.4, `load_pending_arrivals`): `Model::overlay` of a collection also folds the pending `move` and `copy` rows other collections queue into it, each after the rows queued on its item in the collection it leaves, all in append order, so the item shows as the owner would leave it, and a move the owner would park brings nothing.
- **The structure profile** stages a `set-flags` on the message its pending move takes to work/Archive, before the move, so the rows folded first are exercised in every generated store io-pimdir's overlay suite reads.
- **Checks**: the two overlay tests restated from the new text (an `add` in no listing and in `pending_creates`; a move shows in its target with the flags queued on it where it leaves) failed against the earlier overlay and pass now; a new test holds that a move meeting a conflict brings nothing. Broken by hand to see each fail: the arrival folded without the rows before it, pending adds listed among the items, no arrivals, `pending_creates` listing every row.
