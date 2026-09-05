---
cairn: tasks
change: spec-algorithm-audit
---

# Tasks

Triage first: each accepted item becomes its own change with its own delta. Nothing below is landed by this change; a box is ticked when the change that landed it is named beside it.

## Decide

- [x] Concurrency envelope: one process with many handles, or many processes? Settled by `owner-lock-must`: the rule is about processes, the advisory lock is a MUST, and several handles of one process share one lock.
- [x] An object indexed with no referrer: forbidden by the format, or given a grace window? Settled by `collector-recomputes-and-producers-pin` (2026-09-05): legal, and the collector MUST NOT run while a verb of the owner's is between two chunks, the locks covering every other process.
- [x] Is the residual required to survive a crash? Settled by `probes-are-rows` (2026-09-03): it is a row.

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
- [ ] `WITHOUT ROWID` for `objects` and `sources`. Untouched, carried into `algorithm-audit-2026-09-04`.
- [x] Decide what a `DELETE FROM collections` means for the refcounts it orphans: `collector-recomputes-and-producers-pin` (2026-09-05), `delete_collection` followed by `recompute_refcounts` in one transaction, the only sanctioned delete on the table.

## Smaller

- [x] Pin `created_at` to the `strftime` form the schema already uses elsewhere: `created-at-stamped`, which stamps it in the statement rather than only pinning the form, so no producer formats a clock at all.
- [x] Adopt `seq` paging for retained items (§14.1): `retained-page-by-seq`. 1.372 ms to 0.031 ms on a five-thousand-item trash, and the cursor stops being the internal `link_id`.
- [x] Say whether the §7 refcount repair is expected of an implementation or of an operator: of the collector, which runs it first on every collection (`collector-recomputes-and-producers-pin`, 2026-09-05).

## Raised while working the list, not from the original audit

- [x] `store_meta` has **no canonical insert statement**: `init_store_meta`, landed with `change-feed` (2026-09-03).
