---
cairn: change
id: no-write-collects
status: landed
created: 2026-08-25
---

# A store never collects itself

## Why

Two rules of this format contradict each other, and the contradiction destroys data.

§14 step 1 invites a consumer to write a body straight to its sharded path without holding it whole, index it with a byteless `StoreObject`, and attach it later: `store_object` inserts at refcount zero precisely because references come from placement pointers, which a later batch supplies. §14 step 3 then swept every zero-refcount row at the end of that same batch, and step 5 unlinked its blob after the commit. A consumer that stored bodies in one batch and attached them in the next lost them at the end of the first, silently, bytes included.

The second problem is the grace period. §5's orphan sweep had to leave files younger than an hour alone, and the text was explicit that this was correctness rather than caution: a body is written before the row that references it, so a new file is indistinguishable from a live write in flight. It then said locking could not close the window, "the writer holds no lock across the window". That stopped being true when §8 became a MUST (`owner-lock-must`): an owner holds its lock for its lifetime and a producer holds a shared one across its blob write and enqueue. The timer was standing in for a lock that now exists.

And two verbs disagreed about what reclamation is. The automatic sweep ran with no grace and no confirmation on every write, while an operator's orphan sweep needed a grace window and a prompt. The routine operation was the unguarded one.

## What

- §5: an unreferenced object is not a deleted one. A write MUST NOT delete a zero-refcount row nor unlink its blob.
- §5: the refcount sweep and the orphan sweep become one **collector**, which is also the only thing that reclaims. It takes the owner lock it holds and the staging lock exclusively, and the grace period goes with them.
- §14: steps 3 and 5 leave the write algorithm; the commit is step 3.
- §14: `collect_garbage()` is named as an operation, and purge reports rows retired rather than bytes reclaimed.
- queries/objects.sql: the garbage statements are the collector's, and `list_object_hashes` is added, since the orphan half of the collector has to diff the directory against the index.

## Consequence for implementations

An unreferenced object accumulates until a collector runs. That is the bargain: a client that wants it bounded schedules the verb. The reference implementation ships `pimdir gc`; the Android store has no collector yet and its stores will grow until it does.
