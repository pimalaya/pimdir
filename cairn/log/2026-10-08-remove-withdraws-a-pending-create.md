---
cairn: log
change: remove-withdraws-a-pending-create
date: 2026-10-08
---

# A remove on a pending create is guarded

No text change. SYNC §7 already says a `Remove` on a pending create withdraws it, the binding going and the item retained (STORAGE §11), but no vector staged one: io-pimdir tombstoned the create and kept its provisional binding until a sync dropped it (SYNC §3), so a collection no sync visits, an on-device address book, kept it for good. Seen on Pimalaya Android, which worked around it in its bridge.

## Rules

- **SYNC §7, `Remove` on a pending create.** Guarded by vectors/sync/51: a contact created offline and removed before any push leaves no binding and a retained item, in the mutation's own write. Fails on io-pimdir 0.6.0, which leaves the binding.
