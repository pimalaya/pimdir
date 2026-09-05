---
cairn: log
change: collector-recomputes-and-producers-pin
date: 2026-09-05
---

# The refcount invariant holds for a producer, the collector settles before it judges, and a move purges only what the holder has

The producer profile owed §5's invariant for `queue.object_hash` and had no statement to keep it: the pinned body sat at refcount zero behind a foreign key, and the collector's one `DELETE` failed on it, store-wide, until the queue drained. queries/storage/queue/pin_object.sql is the producer's half, and STORAGE §15.1 names it. The collector MUST `recompute_refcounts` before it lists garbage, so a count a writer left behind never decides a delete, and MUST NOT run while a verb of its own is between two chunks, a body streamed in one chunk having no pointer until the next; that closes the item the Aug 25 audit left open.

Two data-loss paths in retention closed with them. `held_elsewhere` purged the retiring row whenever another collection of the account held the identity live, bodies unread: two calendars holding one `UID` with different bodies lost one, and a `Meta`-only holder let the only hydrated body go. It is bound to the retiring `object_hash` now and answers only for a holder carrying it, or when the retiring row has none. A revive adopted the incoming content unconditionally, so a `Meta` fetch reviving a retained message dropped the body §11 promised to keep; the body stays when the placement carries none.

`delete_collection` is the one sanctioned delete on `collections`, followed by `recompute_refcounts` in its transaction, replacing a bare cascade that left pins high. A blob's temporary file is named uniquely to its writer, two processes storing one body having shared `.<hash>` and renamed each other's half-written bytes. STORAGE §5, §11, §14, §15.1; GUIDE §4 to §8, §13. Guarded by checks/invariants.sh.
