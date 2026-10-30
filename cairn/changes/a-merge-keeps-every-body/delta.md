---
cairn: delta
change: a-merge-keeps-every-body
---

## MODIFIED Requirements

### Requirement: STORAGE §15.3 `update`
`{ "v": 1, "seq": n, "object": hash, "if_match": hash? }`. With `if_match`, the owner MUST park the row, naming both bodies, when the item's current body is not `if_match`. The payload stays at `v` 1: the field is optional and its absence is the behaviour before it.

#### Scenario: two producers edit one card
- GIVEN a card at c2, which the first of two queued `update`s stating `if_match` c1 left
- WHEN the second, c3 over c1, is applied as an `Edit` carrying `if_match` c1
- THEN it is refused, staging nothing, and the drain parks it (vector 87)

### Requirement: SYNC §4 `SetFlags`
`SetFlags { handle, add, remove }`: add the flags of `add` and remove those of `remove`, leaving every other flag the member holds. The engine derives both from the merged flags against the set the source holds (the listed one, else the base). The idempotency key's `set-flags` fields are `add`, then `remove`, each a flag set.

### Requirement: STORAGE §15.2 An unreadable body
An `add` or an `update` whose body cannot be read MUST be retried, then parked, and MUST NOT be applied without its body; SYNC §7's `Add` MUST fail, staging nothing.

#### Scenario: a blob gone missing
- GIVEN a queued `add` naming m1, whose row is held and whose blob is not
- WHEN it is applied
- THEN it fails and stages no item (vector 88)

### Requirement: STORAGE §5 The agreed body is counted
`objects.refcount` counts `bindings.shared_object` as it counts `bindings.base_object`; the column references `objects(hash)`. `recompute_refcounts`, `collection_holds_objects` and `release_bases_before` follow; reconciliation runs `repair_shared_objects` and recounts after its backfills.

#### Scenario: the ancestor outlives the item's body
- GIVEN a binding whose `shared_object` is c1 while the item holds c2 and no base names c1
- WHEN the collector runs
- THEN c1 is spared, and falls to it once the binding agrees with c2 (checks/invariants.sh "shared: ...")

## ADDED Requirements

### Requirement: SYNC §9 The agreed body stays where it was
An upsert carrying no body, and one leaving the item conflicted, MUST NOT move its binding's `shared_object`. An item holding no body has changed for every binding whose agreed body names one; an upsert carrying no body over an item holding one disagrees with it. An upsert carrying a body over an item holding none, from a binding whose base names no body, fills the item, an item conflict standing. A divergence whose incoming body is not carried MUST be recorded as `manual` records one, whatever the policy, its `conflict_object` fetched by the upgrade (SYNC §6).

#### Scenario: both servers edit, neither listing carries the body
- GIVEN a and b agreed on c1; a pulled an edit with no body, emptying the item
- WHEN b's upgrade fetches b's edit c3, then a's upgrade fetches a's c2
- THEN the item is conflicted with c3 (vector 81), then holds c2 with the conflict standing (vector 82), and both bindings keep c1 as their pinned ancestor

#### Scenario: a body-less pull over another source's edit
- GIVEN b folded c3 into the item and a, under `PreferRemote`, pulls an edit with no body
- WHEN the write absorbs it
- THEN the item keeps c3 and is conflicted with no `conflict_object` (vector 83), which a's upgrade fills with a's body (vector 84); nothing pushes c3 over a's unread edit

### Requirement: SYNC §5 and §9 A policy's loser is kept
The body a policy does not adopt (the shared body `prefer-incoming` replaced, the incoming body `prefer-existing` refused, the local edit `PreferRemote` dropped) MUST be kept as a retained item beside the one it lost to, under the key minted over the settling binding's handle, and reported `Overruled`.

#### Scenario: prefer-incoming
- GIVEN vector 28's divergence under `prefer-incoming`
- WHEN b's edit settles it
- THEN the item takes c2 and c3 is retained under `dup:<uid>#b.vcf` and reported (vector 85; vector 86 for `prefer-existing`, vector 14 for `PreferRemote`)
