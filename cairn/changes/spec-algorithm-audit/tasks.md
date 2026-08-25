---
cairn: tasks
change: spec-algorithm-audit
---

# Tasks

Triage first: each accepted item becomes its own change with its own delta. Nothing below is landed by this change.

## Decide

- [ ] Concurrency envelope: one process with many handles, or many processes? Decides whether §8 needs the advisory lock, the delete-first drain guard, or both.
- [ ] An object indexed with no referrer: forbidden by the format, or given a grace window?
- [ ] Is the residual required to survive a crash?

## Correctness of the format

- [ ] Scope `lookup_objects` by collection (§14), and say why deduplication across collections stays on the `list_object_placements` axis.
- [ ] State base presence explicitly (§13): `base_present` column, or `null` JSON distinct from SQL `NULL`.
- [ ] Require the parent directory fsync after the blob rename (§5).
- [ ] Make the queue drain's delete the guard rather than the epilogue (§15), independent of the §8 lock.
- [ ] Drop or make true the "swept by the next batch" promise for orphan blobs (§14 step 5).

## Complexity claims and schema

- [ ] Replace `recompute_refcounts` with the `UNION ALL` + `GROUP BY` form; correct the stated complexity.
- [ ] Add `items_by_conflict_object`, `queue_by_object`, `items_by_seq_global`, `bindings(collection, source, handle)`.
- [ ] Add `CHECK (refcount >= 0)`; make the sweep predicate `<= 0`.
- [ ] State §14's write step as a batch-scoped load rather than a collection load.
- [ ] Scope the refcount-zero sweep to the hashes the batch touched.
- [ ] Permit the blob write before `BEGIN` (§14 step 1): content-addressed and immutable, so a crash leaves an orphan file at worst.
- [ ] `WITHOUT ROWID` for `objects` and `sources`; reconsider the column order of `items_retained`.
- [ ] Decide what a `DELETE FROM collections` means for the refcounts it orphans.

## Smaller

- [ ] Pin `created_at` to the `strftime` form the schema already uses elsewhere.
- [ ] Adopt `seq` paging for retained items (§14.1).
- [ ] Say whether §7's refcount repair is expected of an implementation or of an operator.
