---
cairn: log
change: the-freeze-plan
landed: 2026-11-20
---

# The generator's engine, third part: moves, copies, deliveries and landings

The third part of plan 2's "The scripted remote states", of cairn/changes/the-freeze-plan. No part of the standard moves.

- **Origins and destinations** (generator/src/engine.rs, SYNC §3): a pending create carries the origin this source's based binding of its identity in another collection gives, under a handle no listing gave provisionally and holding its body as the base, and pushes an `Add` copying from it; a tombstone carries the destination this source's pending or delivered create of its identity gives, and pushes a `Remove` relocating there. Both keyed with their `origin` and `to` (SYNC §4), held to vectors/sync, which now types every push but an `Add` naming no body.
- **Deliveries and landings** (SYNC §5, §6): an accepted relocation delivers the destination's create, a base naming nothing; a delivered create owes nothing; a listing naming a member whose hint a pending or delivered create of this source holds, its message agreeing, lands it: the binding moved to the listed handle, the base the listed flags and the staged body, the staged flags kept, reported `Created`.
- **A move is not a loss** (STORAGE §11.1): a `Deleted` drop whose identity is held live in another collection of the account with the same body, or with an agreeing message for a bodiless row, purges the row; the model counts its purges, which the writer restores through empty scratch collections created and deleted, the one write counting in `purges` that leaves no row, and a history's seq gaps and shared seqs whose first holder a purge took are written as the model holds them.
- **A history** over two mailboxes: a move whose source syncs first, a copy, a move whose target syncs first, then quiet runs.
- **Checks**: tests state each run from SYNC (the relocating remove and its outcome, the purge, the delivered create, the landing reported `Created` and not `Added`, the copy's origin, the plain remove once the create landed, quiet runs); each step's store is written and self-checked, its purge count included. Broken by hand to see each fail: no destination, no origin, no purge.
