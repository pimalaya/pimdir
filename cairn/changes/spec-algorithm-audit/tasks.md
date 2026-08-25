---
cairn: tasks
change: spec-algorithm-audit
---

# Tasks

Triage first: each accepted item becomes its own change with its own delta. Nothing below is landed by this change; a box is ticked when the change that landed it is named beside it.

## Decide

- [x] Concurrency envelope: one process with many handles, or many processes? Settled by `owner-lock-must`: the rule is about processes, the advisory lock is a MUST, and several handles of one process share one lock.
- [ ] An object indexed with no referrer: forbidden by the format, or given a grace window? The mirror image of `orphan-blobs-are-swept-by-nobody`, which settled the file-with-no-row case (an operator sweep behind a grace period) and deliberately left this one.
- [ ] Is the residual required to survive a crash?

## Correctness of the format

- [x] Scope `lookup_objects` (§14). Landed scoped by **account** rather than by collection: across collections the answer is what the read exists for, one message in two mailboxes being one body downloaded once, so collection was the wrong axis and account is the one a link id is trustworthy on.
- [x] State base presence explicitly (§13): `base_present`.
- [x] Require the parent directory fsync after the blob rename (§5).
- [x] Make the queue drain delete the guard rather than the epilogue (§15): **already landed before this audit was written**. §15.2 states it, and `claim_action` is the statement, a `DELETE ... RETURNING id` running first in the apply transaction with the reasoning written beside it. The audit item was stale, not open.
- [x] Drop or make true the "swept by the next batch" promise for orphan blobs (§14 step 5): `orphan-blobs-are-swept-by-nobody`. It was false, and §5 gained the sweep that is actually the answer.

## Complexity claims and schema

- [x] Replace `recompute_refcounts` with the `UNION ALL` + `GROUP BY` form; correct the stated complexity: `recompute-refcounts-linear`. Measured 80.3 s to 121 ms at twenty thousand items.
- [x] Add `items_by_conflict_object`, `queue_by_object`, `items_by_seq_global`, `bindings(collection, source, handle)`.
- [x] Add `CHECK (refcount >= 0)`; make the sweep predicate `<= 0`: `refcount-floor`.
- [x] State the §14 write step as a batch-scoped load rather than a collection load.
- [x] Scope the refcount-zero sweep to the hashes the batch touched: **not needed, measured**. The partial index `objects_garbage` already makes both halves O(garbage). At the steady state a batch actually meets (every object live, nothing to collect) the full list-plus-delete sweep is flat at 6.9 µs across 10 000, 100 000 and 400 000 objects. Scoping it would add a bound parameter and a JSON array to save nothing.
- [x] Permit the blob write before `BEGIN` (§14 step 1): `orphan-blobs-are-swept-by-nobody`, which is what made the justification true.
- [x] Reconsider the column order of `items_retained`: `retained-page-by-seq` re-ordered it to `(collection, seq)`, measured across every retained read. The extra `(retained_at)` index the audit proposed alongside it was **rejected on measurement**: 54.88 ms against 56.45 ms at 500 collections, because the purge cost is the per-row foreign-key check on `bindings`, not the lookup.
- [ ] `WITHOUT ROWID` for `objects` and `sources`. Untouched, and the only remaining schema item.
- [ ] Decide what a `DELETE FROM collections` means for the refcounts it orphans. The cascade takes items and bindings without releasing their pins, so the counts are left too high and the bodies never collected.

## Smaller

- [x] Pin `created_at` to the `strftime` form the schema already uses elsewhere: `created-at-stamped`, which stamps it in the statement rather than only pinning the form, so no producer formats a clock at all.
- [x] Adopt `seq` paging for retained items (§14.1): `retained-page-by-seq`. 1.372 ms to 0.031 ms on a five-thousand-item trash, and the cursor stops being the internal `link_id`.
- [ ] Say whether the §7 refcount repair is expected of an implementation or of an operator. `orphan-blobs-are-swept-by-nobody` answered the same question for the blob sweep (an operator), so this one now has a precedent to follow or to deviate from deliberately.

## Raised while working the list, not from the original audit

- [ ] `store_meta` has **no canonical insert statement**. The one row that fixes `hash_algo` for the whole store is written by ad-hoc code in every implementation, which is the same hole §16's vectors exist because of. Needs a seventh queries/ file and a §4.4 change.
