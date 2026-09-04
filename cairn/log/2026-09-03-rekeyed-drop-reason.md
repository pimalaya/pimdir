---
cairn: log
change: rekeyed-drop-reason
date: 2026-09-03
---

# A rebuild drops with reason Rekeyed, since an accepted add already supersedes

The sync part had made a `Superseded` drop the signal that a batch is a rebuild, and a sync's accepted add drops its provisional handle with the same reason once the server assigns one. Every create would have bumped the generation.

A drop now carries one of three reasons: `Deleted`, the member is gone; `Superseded`, a provisional handle an accepted add replaced; `Rekeyed`, a handle a rebuild renumbered. Both of the last two license the binding to move (STORAGE §10), only the last is the epoch bump (STORAGE §12, SYNC §8). SYNC §10 names the three, GUIDE §5 and §11 follow, and the rekey vector's note says which drop it expects.
