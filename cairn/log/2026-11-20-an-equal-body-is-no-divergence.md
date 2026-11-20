---
cairn: log
change: the-freeze-plan
landed: 2026-11-20
---

# An equal body is no divergence

The two questions cairn/log/2026-11-20-the-engine-seams-the-generator-found.md left, decided by the freeze plan's lead on 2026-11-20 (the owner may veto), landed in sync-draft-15, no number moving.

## What moved

- **SYNC §6, an item conflict's body read** (normative): a body an upgrade fetches for an item conflict waiting for it, equal to the item's own, is no divergence whatever the policy: the item's conflict clears and the binding takes that body as its base and its `shared_object`, as a binding's own conflict clears on its own body. It landed in `items.conflict_object` under `manual`, a conflict between two equal bodies a person had to settle, on every card a second address book listed at `Meta` shares with the first. §9's "once the missing body is read" says the same.
- **SYNC §9, a joining member changed** (normative, clarified): the source changed when it bound none of the item before the upsert. A member joining without its body is then the unread divergence §9 records as `manual` does, whatever the policy. Vector 187 (the join, `Added` and `Conflicted`, the item conflicted with no `conflict_object`), vector 188 (the upgrade reading the item's own body clears it, the binding based and agreed on it).
- **SYNC §5, a candidate's change is derived before its write** (normative): what the write's fold (§9) leaves a binding owing, the item's body a collection's policy kept over the member's, is pushed by the source's next run, never by the run that pulled. Vector 182 now runs with `push` true and pushes nothing.
- **SYNC §6, a body read under an unread base outside an item conflict** (no rule moves, pinned): vector 133 now states the item and the binding unconflicted after the upgrade reads the base a local edit waited for, under `manual`: a fetch over a placement no item conflict waits on moves the base (§6, "A fetch moves the base"), and the collection's policy meets only an item conflict waiting for that body. The generator's working-tree `revisit` marks such an item conflicted under `manual`, a reading 133 now refuses.
- checks/vectors.py: an upgrade reading, for an item conflict holding no `conflict_object`, a body equal to the item's leaves the item unconflicted ("b.vcf's body read equal to the item's clears the item's conflict" on 188 with the conflict kept). GUIDE §10, §11 and §12 and vectors/README.md follow.

## Guards

- Vectors 187 and 188 fail on io-pimdir 8e09e1c ("bindings rows differ": the join conflicted on its binding; the equal body leaving the item conflicted) and pass on the io-pimdir following this entry (its cairn/log/2026-11-20-an-equal-body-is-no-divergence.md). Vector 182 passes on both and fails on an engine pushing what its own fold left owed.
- `nix flake check path:$PWD`.

## Left

- The generator's model pushes what its own fold leaves owed in the same run, and its upgrade models no item conflict: both its lane's to follow.
