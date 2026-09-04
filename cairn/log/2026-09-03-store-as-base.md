---
cairn: log
change: store-as-base
date: 2026-09-03
---

# The store is the base, sync and search are layers on it

The README, OVERVIEW and STORAGE introduced three parts as peers, each implementable on its own. Only the layers are optional: a sync without the store is a two-way compare that cannot tell a delete on one side from an add on the other, and a search without it is a fan-out to each source's own search with no shared meaning of a match and no offline answer.

README, OVERVIEW §1, STORAGE's introduction, SYNC §1, SEARCH's introduction and GUIDE §1 now say so: an implementation provides the store, may omit either layer, and neither layer is defined without the store. What stays optional inside the store is the bodies.
