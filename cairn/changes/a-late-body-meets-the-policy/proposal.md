---
cairn: change
id: a-late-body-meets-the-policy
status: landed
created: 2026-10-30
---

# A divergence's late body meets the collection's policy

## Why

A follow-up to a-merge-keeps-every-body, decided by the orchestrator of the pimdir stable-release effort (2026-10-30). A divergence whose incoming body the upsert does not carry is recorded as `manual` records one whatever the collection's `conflict` policy (SYNC §9), since no policy chooses between a body and one nobody has read. Once the upgrade fetches that body into `items.conflict_object`, the reason is gone, yet the item stayed conflicted under `prefer-incoming` or `prefer-existing`, waiting for a person on a collection whose owner chose a policy so that nobody would wait.

## What

- SYNC §6 (a conflict's body) and §9: the fetch applies the policy as for a carried body: `manual` records it in `items.conflict_object`; `prefer-incoming` adopts it; `prefer-existing` keeps the shared body; the conflict clears either way, and the body not adopted is kept as a retained item keyed over the handle of the binding whose upgrade fetched it and reported `Overruled`.
- STORAGE §10 and §11: that upgrade clears the item's conflict; the retained body's key.
- GUIDE §11 and §12.
- checks/vectors.py: under a `prefer-` policy no item conflict holds a body.
- vectors/sync/90 (`prefer-incoming`) and 91 (`prefer-existing`).

## Lands in

sync-draft-05 and storage-draft-05 (the §10 sentence).
