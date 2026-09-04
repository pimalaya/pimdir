---
cairn: log
change: handle-names-one-item
date: 2026-09-04
---

# A handle names one item per source

Nothing enforced the other direction of §10's bind-once rule: a write upserting a new link id under a handle another item already held, a hash: key that changed under one DAV resource, inserted a second binding and link_for_handle answered from whichever row SQLite found first. bindings_by_handle is now UNIQUE, and STORAGE §10 says the write retires the old binding first, as a Deleted drop would. §14 and GUIDE §5 resolve every upserted handle into the batch's diff for it.
