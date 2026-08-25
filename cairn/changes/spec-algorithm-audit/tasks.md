---
cairn: tasks
change: spec-algorithm-audit
---

# Tasks

Triage first: each accepted item becomes its own change with its own delta. Nothing below is landed by this change; a box is ticked when the change that landed it is named beside it.

## Decide

- [x] Concurrency envelope: one process with many handles, or many processes? Settled by `owner-lock-must`: the rule is about processes, the advisory lock is a MUST, and several handles of one process share one lock. The drain-guard half is still open below.
- [ ] An object indexed with no referrer: forbidden by the format, or given a grace window? The mirror image of `orphan-blobs-are-swept-by-nobody`, which settled the file-with-no-row case and deliberately left this one.
- [ ] Is the residual required to survive a crash?

## Correctness of the format

- [x] Scope `lookup_objects` (§14). Landed scoped by **account** rather than by collection: across collections the answer is what the read exists for, one message in two mailboxes being one body downloaded once, so collection was the wrong axis and account is the one a link id is trustworthy on.
- [x] State base presence explicitly (§13): `base_present`.
- [x] Require the parent directory fsync after the blob rename (§5).
- [ ] Make the queue drain's delete the guard rather than the epilogue (§15). Still open, and now independent of §8: `owner-lock-must` made the lock a MUST, which removes the race but leaves the claim-first delete as the thing that makes an action exactly-once without depending on it.
- [x] Drop or make true the "swept by the next batch" promise for orphan blobs (§14 step 5): `orphan-blobs-are-swept-by-nobody`. It was false, and §5 gained the sweep that is actually the answer.

## Complexity claims and schema

- [x] Replace `recompute_refcounts` with the `UNION ALL` + `GROUP BY` form; correct the stated complexity: `recompute-refcounts-linear`. Measured 80.3 s to 121 ms at twenty thousand items.
- [x] Add `items_by_conflict_object`, `queue_by_object`, `items_by_seq_global`, `bindings(collection, source, handle)`.
- [x] Add `CHECK (refcount >= 0)`; make the sweep predicate `<= 0`: `refcount-floor`.
- [x] State §14's write step as a batch-scoped load rather than a collection load.
- [ ] Scope the refcount-zero sweep to the hashes the batch touched. Worth re-measuring before doing: the partial index `objects_garbage` holds only what is about to be collected and is empty at rest, so both halves of the sweep may already be O(garbage) rather than O(objects).
- [x] Permit the blob write before `BEGIN` (§14 step 1): `orphan-blobs-are-swept-by-nobody`, which is what made the justification true.
- [ ] `WITHOUT ROWID` for `objects` and `sources`; reconsider the column order of `items_retained`.
- [ ] Decide what a `DELETE FROM collections` means for the refcounts it orphans. The cascade takes items and bindings without releasing their pins, so the counts are left too high and the bodies never collected.

## Smaller

- [ ] Pin `created_at` to the `strftime` form the schema already uses elsewhere.
- [ ] Adopt `seq` paging for retained items (§14.1).
- [ ] Say whether §7's refcount repair is expected of an implementation or of an operator. `orphan-blobs-are-swept-by-nobody` answered the same question for the blob sweep (an operator), so this one now has a precedent to follow or to deviate from deliberately.
