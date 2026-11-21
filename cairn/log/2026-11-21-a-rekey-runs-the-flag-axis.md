---
cairn: log
change: the-freeze-plan
landed: 2026-11-21
---

# A rekey runs the flag axis

The owner's decision on G23 (2026-11-21) and the generator following the spec text on the replay findings io-pimdir's generated suite left on 2026-11-21 (io-pimdir cairn/log/2026-11-21-the-replay-runs-every-history.md).

## What moved

- SYNC §8 (sync-draft-15, edited in place, untagged): **a rekey runs the flag axis on the flags its listing states**. A carried member's listed flags are the remote side of §5's flag axis, the item's flags the local side, the old base's flags the base: the item takes the merge, the binding's base the listed flags; a flag change still owed is the next sync's push, the rekey pushing nothing. G23 read two ways ("carries each placement's [...] flags, base"): the generator kept flags and base as they stood, io-pimdir merged them; the owner chose io-pimdir's reading. Guarded by vectors/sync/195-a-rekey-runs-the-flag-axis-on-its-listed-flags.json (a local `\Flagged` and a remote `\Answered` merged, the base the listed set), vectors/manifest.json restated.

## The generator follows the spec

- G23: `Model::rekey` merges each carried member's flags over the old base (`engine::merge`) and takes the listed flags as the base. `a_rekey_carries_every_placement_onto_its_new_handle_by_link_id` now asserts the merge and the base.
- G24: a rekey's pull of a mutable member its server edited takes the member's summary, addresses and sort key (SYNC §8 "carry it as a pull (§5)", §5's pull making the member's meta the summary and sort key), not the old body's.
- G25: an upgrade reports no event but `Overruled` (SYNC §5); `an_upgrade_reading_a_change_over_an_emptied_item_records_it` asserts none.
- G26: a revival's binding names a `shared_object` only when the member carried a body (STORAGE §10, "never by a pull carrying none").
- G14, turned over: `Model::refresh` treats a binding whose item holds a body differing from its `shared_object` (or its base until it folded once) as propagation owed: pulled whatever the source's policy, `KeepLocal` aside, the divergence the collection's (SYNC §5). `History::bodies`' work/overruled steps now record the item's conflict, not b's; `an_overruling_edit_keeps_the_diverging_body_or_is_refused_unread` follows.

Checks: the generator's cargo tests (82 passed) and `nix flake check path:$PWD`; io-pimdir's tests/generated replays the five findings clean, their `known()` entries lifted.
