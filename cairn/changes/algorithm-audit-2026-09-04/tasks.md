---
cairn: tasks
change: algorithm-audit-2026-09-04
---

# Ledger

A box is ticked when the named change landed the fix and the named check or vector guards it. Verified means reproduced with the canonical SQL before the fix.

## Found by every reader

- [x] Change-feed cursor off by one (verified): `change-feed-cursor-and-stamps`, invariants.sh.
- [x] Duplicate stamps after `stamp_item` without a bump (verified): `change-feed-cursor-and-stamps`, invariants.sh.
- [x] A producer cannot keep the refcount invariant and the collector wedges (verified): `collector-recomputes-and-producers-pin`, `pin_object`, invariants.sh.
- [x] A rename empties the collection from the index (verified): `change-feed-cursor-and-stamps`, `collections_restamp_items`, invariants.sh.
- [x] Per-collection drain breaks append order: `queue-order-and-rollback`, `list_pending_actions`, invariants.sh.
- [x] `KeepBoth` can never land on a DAV server: `compaction-before-the-freeze`, policy removed.
- [x] `is:retained` unreachable: `search-roles-threads-horizon`, removed.
- [x] Idempotency key names a state: `compaction-before-the-freeze`, key log bounded to the chunk.
- [x] Cross-source divergence under-determined, `items.conflicted` never cleared: `projection-gates-on-the-item-conflict`, vector 28.
- [x] Horizon roll binds the wrong horizon, compares formats as text, skips tasks: `search-roles-threads-horizon`, `items_to_reexpand`.

## Data loss or silent divergence

- [x] Claim-first then park in one transaction loses the action (verified): `queue-order-and-rollback`.
- [x] A local content edit over a remote delete is retained silently: `deletes-and-the-trash`, vector 16.
- [x] A deleted item is offered as `Created` to a source lacking it: `projection-gates-on-the-item-conflict`, rule 3.
- [x] `items.conflicted` does not gate the projection: `projection-gates-on-the-item-conflict`, rule 1, vector 28.
- [x] A rekey drops pending creates: `fallback-keys-mint`, SYNC §8, vector 29.
- [x] A connector cannot signal a handle-space change: `fallback-keys-mint`, SYNC §4.
- [x] `held_elsewhere` purges without comparing bodies, and past a bodiless holder: `collector-recomputes-and-producers-pin`, invariants.sh.
- [x] Revive discards the retained body on a `Meta` fetch: `collector-recomputes-and-producers-pin`, STORAGE §11.1.
- [x] Fallback keys collide on the primary key: `fallback-keys-mint`, vector 31, summaries.json.
- [x] A relocation races the target's pending create and duplicates: `compaction-before-the-freeze`, creates wait for probes, vector 25.
- [x] Linking by `Message-ID` adopts different bytes permanently: `projection-gates-on-the-item-conflict`, size witness.
- [x] UID-less cards ping-pong between two servers: `compaction-before-the-freeze`, `hash:` keys not offered.
- [x] `origin_for_link` and `destination_for_link` not account-scoped: **open**, see below.

## Correctness

- [x] Base after a fetch unstated, vectors 07 and 21 read as disagreeing: `projection-gates-on-the-item-conflict`, vector 30.
- [x] §5 against §6 on a create meeting a member: `projection-gates-on-the-item-conflict`.
- [x] `Conflict` outranks `Tombstone`: `projection-gates-on-the-item-conflict`, vector 32.
- [x] Handle order undefined: `fallback-keys-mint`, byte order.
- [x] Rekey pairs duplicates by handle order alone: `fallback-keys-mint`, body hash first.
- [x] Rekey handle overlap needs drops before upserts, one batch: `fallback-keys-mint`, SYNC §8, §10.
- [x] Delete policy decided by configuration loops: `deletes-and-the-trash`, decided per item.
- [x] Refused against rejected delete ambiguous: `deletes-and-the-trash`.
- [x] Lost `Update` record becomes a conflict with yourself: `projection-gates-on-the-item-conflict`, self-resolution.
- [x] Tombstone of a pending create pushes against a provisional handle: `deletes-and-the-trash`.
- [x] Tombstone held by a non-pushing source is invisible: `deletes-and-the-trash`, trash lists it.
- [x] `remove` of an item no source binds skipped for ever: `queue-order-and-rollback`.
- [x] Rename leaves a stale `to` in queued moves: `queue-order-and-rollback`, `rename_queue_targets`.
- [x] `add` on a tombstone collides on insert (verified): `queue-order-and-rollback`, revives.
- [x] Provisional handles have no namespace: `fallback-keys-mint`.
- [x] Mutable hint change under one handle ignored: `fallback-keys-mint`.
- [x] Immutable kind fetched beside a linked copy stays `Dirty` for ever: `projection-gates-on-the-item-conflict`, SYNC §9.
- [x] Placement with no body projects `Dirty` for other sources: `projection-gates-on-the-item-conflict`, rule 4.
- [x] Flag merge undefined, no base undefined: `deletes-and-the-trash` (SYNC §5), vectors 26 and 27.
- [x] `from:` without an `@` loses its role: `search-roles-threads-horizon`.
- [x] Threads split on an absent root, no parent index, re-key cascade, cross-account join: `search-roles-threads-horizon`.
- [x] `delete_placement` leaves flags and occurrences: `search-roles-threads-horizon`, cascades.
- [x] Single events beyond the horizon never expanded: `search-roles-threads-horizon`.
- [x] Indexer poisons an object on a missing blob: `search-roles-threads-horizon`.
- [x] `objects_gone` never runs after a plain collect: `change-feed-cursor-and-stamps`, `objects_count_collect`.
- [x] No collection removal operation; bare cascade leaves pins high: `collector-recomputes-and-producers-pin`, `delete_collection`, invariants.sh.
- [x] Collector between two chunks of an upgrade: `collector-recomputes-and-producers-pin`.
- [x] Shared temporary blob name across writers: `collector-recomputes-and-producers-pin`.
- [x] Schema CHECKs missing: `compaction-before-the-freeze`.
- [x] Paging indexes carry deleted rows: `compaction-before-the-freeze`, partial `items_by_sort`.
- [x] Unbounded retries in the drain and unbounded rejected adds: `queue-order-and-rollback`, SYNC §5.
- [x] Statements named in no document: `checks-and-the-ledger`, names.sh.

## Open

- [ ] `origin_for_link` and `destination_for_link` join no account. Two accounts each naming their source `imap` share the namespace. Decide between an account join in both statements and a rule that `sources.source` is unique across the store; the second is one sentence, the first two statements and a vector with two accounts. Neither landed tonight because the vectors carry no two-account sync case to pin it and the reference engine keys its sources per account already.
- [ ] A purge log table in place of the `purges` counter, so a consumer reconciles O(purged) rather than O(index) after every move. A design change to §4.5 with a new table; worth a proposal.
- [ ] A persisted pending bit on bindings, so a delta sync no longer loads a whole collection to find its non-`Clean` placements. §1 promises hundreds of thousands of items; a proposal.
- [ ] `SetFlags` replaces absolutely, so a server-side flag change between enumeration and push is overwritten; a delta form (added, removed) or a modseq precondition is a seam change for every connector.
- [ ] `level` could be derived from body and summary presence rather than claimed; a schema change readers depend on, after the freeze or never.
- [ ] `WITHOUT ROWID` for `objects` and `sources`, carried over from the Aug 25 ledger, unmeasured.
- [ ] Reader `?mode=ro` on a WAL store still needs write access to the directory for the shm; a sentence in STORAGE §8 once someone has hit it.
- [ ] Millisecond stamps against second-precision cutoffs in `purge_retained_before`; a sentence in §11.2 saying the cutoff carries `%f`.
