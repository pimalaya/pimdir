---
cairn: delta
change: a-late-body-meets-the-policy
---

## MODIFIED Requirements

### Requirement: SYNC §6 A conflict's body
An item conflict holding no `conflict_object` is revisited by the upgrade, and the body fetched is settled by the collection's `conflict` policy as a carried one would have been: under `manual` it MUST land in `items.conflict_object`; under `prefer-incoming` the item adopts it, under `prefer-existing` keeps its own, the conflict cleared and the body not adopted kept and reported `Overruled`.

#### Scenario: the late body under prefer-incoming
- GIVEN an item conflict recorded under `prefer-incoming` for want of the incoming body
- WHEN the binding's upgrade fetches that body
- THEN the item adopts it, its conflict clears, the shared body is retained under the key minted over the binding's handle and reported `Overruled` (vectors/sync/90; 91 under `prefer-existing`)
