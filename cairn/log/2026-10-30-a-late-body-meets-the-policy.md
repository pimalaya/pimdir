---
cairn: log
change: a-late-body-meets-the-policy
date: 2026-10-30
---

# A divergence's late body meets the collection's policy

A follow-up to a-merge-keeps-every-body, decided by the orchestrator. A divergence whose incoming body is not carried is recorded as `manual` records one whatever the policy, and stayed so under `prefer-incoming` or `prefer-existing` once the upgrade fetched the body, waiting for a person on a collection whose policy says nobody waits.

- **SYNC §6, §9** (normative): the upgrade fetching an item conflict's body settles it by the collection's policy as for a carried body: `manual` records it in `items.conflict_object`; `prefer-incoming` adopts it; `prefer-existing` keeps the shared body; the conflict clears, and the body not adopted is kept as a retained item keyed over the handle of the binding whose upgrade fetched it, reported `Overruled`. Guarded by vectors 90 (`prefer-incoming`) and 91 (`prefer-existing`), and by checks/vectors.py, which fails any case leaving an item conflict holding a body under a `prefer-` policy.
- **STORAGE §10, §11** (normative): that upgrade clears the item's conflict; the retained body's key.
- **GUIDE §11, §12** (informative) follow.

A copy of 90 written as the rule of the morning reads (the item keeping c3, conflicted, c2 in its `conflict_object`) passes the check of the morning and fails this one ("under prefer-incoming, an item conflict holds no body"). No schema or statement changes. `nix flake check path:$PWD` passes. io-pimdir follows in its cairn.
