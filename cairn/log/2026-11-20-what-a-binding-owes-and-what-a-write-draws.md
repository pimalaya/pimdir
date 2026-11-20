---
cairn: log
change: the-freeze-plan
landed: 2026-11-20
---

# What a binding owes and what a write draws

Six seams the generator's model and io-pimdir's replay against it found (the lead's queue of 2026-11-20, G12 to G15 among them), decided by the lead where the text left a choice (the owner may veto), landed in sync-draft-15 and storage-draft-15, no number moving.

## What moved

- **SYNC §5, a lost push carried** (normative, stated): a member carrying, at a revision the base does not hold, the very body the placement holds over that base is the push whose record was lost, as a fetched one is: whatever the policy the binding adopts the listed revision and that body as its base, nothing recorded, pushed or reported. Vector 189.
- **SYNC §5 and §8, a rekey's arrival** (normative, changed): a member no old binding resolves to is named in the rekey's batch as a page names one and reported `Added`; §5 said a rekey reported nothing but `Overruled`, so a message arriving during a renumbering was never reported. Vector 190; vectors runners compare a rekey's events.
- **SYNC §9, a `hash:` key is offered to nobody** (no rule moves, pinned): vector 191, an item under a `hash:` key bound by one source, the other syncing, no `Add` derived. checks/vectors.py refuses an `Add` a sync pushes under a `hash:` key unless its source binds it ("under a hash: key is its source's own create, never an offer").
- **SYNC §5, what a binding owes as propagation** (normative, G14): a both-changed binding whose local body another source folded into the item (the item's body other than its `shared_object`, its base before it folded once) owes propagation, not an edit of its own: whatever its source's policy, `KeepLocal` aside (the store being authoritative), the member is pulled and the write's fold settles the divergence by the collection's `conflict` (§9). It read as the source's both-changed conflict. Vectors 192 (`prefer-incoming` adopting the server's body under the source's `manual`) and 193 (the collection's `manual` conflicting the item, never the binding). Vectors 183 and 193 now state the item's sort key before and after: an item keeping its body under a divergence keeps the summary and sort key of that body, never the incoming one's.
- **SYNC §9, a kept body's own rows** (normative, G12): a retained item keeping a body a policy did not adopt carries the summary and sort key its own bytes give (STORAGE Annex A). Vector 117 states the kept body's sort key (`jane doe-smith`).
- **STORAGE §9.1, the order a write draws seqs in** (normative, G15): first each new item its upserts name, in the batch's order, then each body it keeps, in the order kept, so every owner numbers a batch alike. Vector 194 (a member named, seq 2, before the body kept, seq 3).
- GUIDE §10, §11 and §12, vectors/README.md follow.

## Guards

- On io-pimdir 6678962: 190 (no rekey events), 191 (an `Add` offered under `hash:`), 117 (the kept body under the item's sort key), 192 ("events differ", the binding conflicted under the source's `manual`) and 193 ("bindings rows differ") fail; 183 and 193 failed again on the item's sort key, moved to the incoming body's; 189 and 194 pass on it already. All pass on the io-pimdir following this entry (its cairn/log/2026-11-20-what-a-binding-owes-and-what-a-write-draws.md).
- `nix flake check path:$PWD`.

## Left

- G16 and G17 of io-pimdir's replay, not in this queue.
