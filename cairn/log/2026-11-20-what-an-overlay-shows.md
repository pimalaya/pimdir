---
cairn: log
change: the-freeze-plan
landed: 2026-11-20
---

# What an overlay shows

The overlay lines of the freeze plan, with the questions the generator lane and io-pimdir's generated suite raised (G4, G5, G6, and the generator's reading of SYNC §7).

## What moved

- **STORAGE §15.4** (normative, G5): an overlay of a collection also holds what other collections' pending `move` and `copy` rows bring into it, read by the new statement `load_pending_arrivals` (by `target_collection`, the moves and copies alone, in append order): the item shows there as the owner would leave it, the rows queued on it where it leaves folded in first, a `move` taking it out of that collection and one the owner would park bringing nothing. io-pimdir showed it so; the generator folded the target's own rows alone.
- **STORAGE §15.4** (normative, G4): a pending `add` shows in no listing of items, the `seq` of what it creates being the owner's to draw (§9.1): a reader shows it apart, as the create its row stages, never under a guessed `seq`. io-pimdir lists them apart (`pending_creates`).
- **SYNC §7**: a `Remove` withdrawing a pending create retains the item with `retained_by` the create's source, whose removal retired it, which vector 51 pinned and no text said.
- **Vectors**: 178, a move stages its target's pending create under its source's binding, the provisional handle and no base, the two rows agreeing on the summary sharing seq 1; 179, flags set on a pending create apply to it, the create staying one; 180 (G6), an ordinary local edit moves its binding's `shared_object` to the body the item takes, its base staying, the other source's agreement point unmoved; 177 now pins an add's `shared_object` on the body it carries. None moves a rule; each pins what the text said and no vector held.
- GUIDE §13 names `load_pending_arrivals`; queries/signatures.json restated; checks/invariants.sh runs the statement ("a target reads the moves and copies queued into it in append order, never a row queued on it").

## Guards

- checks/invariants.sh and checks/names.sh for the statement; vectors/sync/178 to 180 pass on io-pimdir.
- The generator's oracle states an expectation for every read statement, so its test fails ("no expectation for storage/read/load_pending_arrivals") until the generator lane states one: routed by the lead.

## For the owner

- A `copy` or a `move` whose binding's source does not sync the target stages the target's create under that source all the same (SYNC §7 names no source for it; io-pimdir uses the run's), against §15.2's "a store-wide drain thus never binds a source to a collection it does not sync": that source never pushes it, another source of the target is offered the item and pushes it, and the stray pending create stays. Recommendation: stage it under a source syncing the target, the one an `add` runs as, with no origin unless that source holds it.
- The overlay's §15.6 backstop (a row a capability declared since enqueuing parks) is left to the drain: a reader holds no performer, and the producer's gate decided at enqueue time.
