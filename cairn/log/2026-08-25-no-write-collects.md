---
cairn: log
change: no-write-collects
date: 2026-08-25
---

# A store never collects itself

The format told a consumer to stream a body to its sharded path, index it, and attach it in a later batch (§14 step 1), and then swept every zero-refcount row at the end of each write (§14 step 3). Both rules were normative, and together they destroyed the body between the batch that indexed it and the batch that was going to reference it: silently, bytes included, in the pattern the format itself recommends for a large body.

## What moved

- **§5: an unreferenced object is not a deleted one.** A write MUST NOT delete a zero-refcount row and MUST NOT unlink its blob. Refcounts are still maintained exactly as before; only the reclamation left.
- **§5: one collector, not two sweeps.** The refcount sweep and the orphan sweep were the same operation seen from two sides — once the rows are gone, their bodies *are* orphans — and they are now one thing that deletes the unreferenced rows and unlinks every file the index does not name.
- **The grace period is gone**, replaced by the locks §8 now requires (`owner-lock-must`). The old text was right that the window is real and that a young file cannot be told from a live write by inspection, and right in its own terms that "the writer holds no lock across the window": that was true when nothing took a lock. It is not any more, and a timer standing in for a lock is a guess where there is now an answer. A period-prefixed temporary file is stated as not-an-orphan, since it belongs to a writer that has not renamed it into place.
- **§14: steps 3 and 5 are gone**, and the commit is step 3. The step-1 note about the early blob write now points at the writer's lock rather than at the file's age.
- **§14 and §11.2: a purge reports rows retired.** The bytes belong to whatever frees them, which is the collector; a purge releases a body rather than reclaiming one. `retained_bytes` is an upper bound on a purge *followed by a collection*.
- **queries/objects.sql**: the two garbage statements are documented as the collector's rather than a write's, and `list_object_hashes` is added — the orphan half cannot be derived from the database, so the collector needs the index's whole hash set to diff the directory against.

## What this supersedes

`orphan-blobs-are-swept-by-nobody` landed earlier the same day and made the grace period normative, on the reasoning that "locking does not close this: the writer holds no lock over the window between its blob write and its commit". That was true when it was written, and it is the reason this could not have been done in that change: nothing took a lock. `owner-lock-must` then made both locks a MUST, and the window an owner or a producer widens is now a window it holds a lock across. The earlier entry stands as written; this is the correction that its own last sentence was waiting for.

The half of it that does not move is the half that matters most: an orphan is reachable only by reading the directory, no write batch reads the directory, and a store that never runs the collector grows without bound while passing every check it has. That reproduction is still the reason this section exists.

## Who is conformant

io-pimdir lands this as `manual-gc`, with `pimdir gc` as the verb and its `check --fix` demoted from reclaiming to repairing. The Android store has no collector at all: its stores now grow until one exists, which is the cost of the bargain and worth stating plainly rather than discovering as disk usage.
