---
cairn: tasks
change: a-late-body-meets-the-policy
---

# Tasks

- [x] SYNC §6 and §9: the policy applied to the fetched body, the loser's key
- [x] STORAGE §10 and §11: the conflict cleared by that upgrade, the retained body's key
- [x] GUIDE §11 and §12
- [x] checks/vectors.py: no item conflict under a `prefer-` policy holds a body, failing on 90 written as `manual` would leave it
- [x] vectors/sync/90-a-fetched-conflict-body-meets-prefer-incoming.json and 91-a-fetched-conflict-body-meets-prefer-existing.json
- [x] Log entry
- [x] `nix flake check path:$PWD`

Followers, tracked in their repositories: io-pimdir (the upgrade's item-conflict fetch reads the collection's policy, keeps the loser and reports `Overruled`).
