---
cairn: log
change: move-destination-derived
date: 2026-09-04
---

# A move's destination is derived, and a relocation lands the create

The engine carried a move's destination on the tombstone's origin, which no store column persisted, so through a conforming store every remove was a plain delete and a source synced before its target lost an un-hydrated item: no origin left to copy from, no body to upload. SYNC §3 now derives a **destination** the way it derives an origin, from the pending create the same source holds elsewhere, through the new destination_for_link statement.

Two rules close the loop. SYNC §4: a connector that cannot relocate a Remove carrying `to` rejects it, never deletes. SYNC §6: a fetched hint held by a pending create of the same source lands that create, a Superseded drop of the provisional handle, instead of minting a second copy. Vectors 20 and 21 pin both; GUIDE §9 to §11 follow.
