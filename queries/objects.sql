-- pimdir objects: the content-addressed body index and its reference counting.
-- The bytes live in blob files (SPEC.md §5); these rows are the index + refcount.
--
-- Canonical reference statements servicing the store operations (SPEC.md §14).
-- An implementation SHOULD use them verbatim and MAY substitute an equivalent
-- that preserves the same invariants (SPEC.md §7). Column encodings are in
-- SPEC.md §13. Named parameters use `:name`.

-- name: store_object
-- Index an object (write-op StoreObject). Its bytes live in the blob file
-- (SPEC.md §5), written either by this batch or, for a byteless StoreObject,
-- already streamed there by the consumer before the op was emitted. The
-- refcount is settled later in the batch (SPEC.md §14).
INSERT INTO objects(hash, size, refcount) VALUES(:hash, :size, 0)
ON CONFLICT(hash) DO UPDATE SET size = excluded.size;

-- name: lookup_objects
-- Resolve link ids to a hydrated body hash. :links is a JSON array of link ids.
--
-- Scoped to one account (:account, the caller's own, NULL in a single-account
-- store), which is the axis a link id is trustworthy on. Across collections the
-- answer is exactly what this read exists for: one message filed in two
-- mailboxes is one body, downloaded once. Across accounts it is not a fact at
-- all, since two unrelated servers may mint the same vCard UID (SPEC.md §9.2),
-- and answering with the other account's body hands one account's content to the
-- other's sync, which then believes the item is hydrated and never fetches the
-- real one. A single-account store writes no account, so the filter is a no-op
-- and the dedup is whole-store.
SELECT i.link_id, i.object_hash FROM items i
JOIN collections c ON c.id = i.collection
WHERE i.object_hash IS NOT NULL
  AND i.link_id IN (SELECT value FROM json_each(:links))
  AND c.account IS :account;

-- name: recompute_refcounts
-- Recompute every object's refcount from the pointers that pin it: an item's
-- shared or conflict body, a source's base, or a pending queue action's body
-- (SPEC.md §15). O(items+bindings+queue), run once at the end of a write batch.
--
-- The four pointer columns are gathered into one stream and counted in a single
-- grouped pass, which is what makes the complexity above true. Counting instead
-- with a correlated subquery per object row costs O(objects x items): the OR
-- across object_hash and conflict_object is a disjunction no single index
-- serves, so the planner scans items once per object row. On a store of twenty
-- thousand items that form took 80 seconds, and this one 121 ms.
--
-- The left join is what settles an object no pointer names any more: it counts
-- zero rather than going unvisited, which is how a released body reaches the
-- sweep below. A row already holding its true count is left alone, so the
-- statement writes only the drift it found.
UPDATE objects SET refcount = counted.n
FROM (
  SELECT o.hash AS hash, count(r.hash) AS n FROM objects o
  LEFT JOIN (
    SELECT object_hash AS hash FROM items WHERE object_hash IS NOT NULL
    UNION ALL SELECT conflict_object FROM items WHERE conflict_object IS NOT NULL
    UNION ALL SELECT base_object FROM bindings WHERE base_object IS NOT NULL
    UNION ALL SELECT object_hash FROM queue WHERE object_hash IS NOT NULL
  ) r ON r.hash = o.hash
  GROUP BY o.hash
) AS counted
WHERE counted.hash = objects.hash AND objects.refcount != counted.n;

-- name: adjust_refcount
-- Adjust one object's refcount by the net change in pointers a batch made to
-- it (SPEC.md §14): the O(changes) alternative to recompute_refcounts, for an
-- implementation that diffs its writes. Preserves the same §5 invariant.
UPDATE objects SET refcount = refcount + :delta WHERE hash = :hash;

-- name: list_garbage_objects
-- Objects no item/binding pins; blob files unlinked before the rows go. The
-- predicate is `<= 0` rather than `= 0` to match the partial index
-- objects_garbage exactly, so neither statement scans the table. Under the
-- refcount floor (SPEC.md §7) the two select the same rows; the wider one is for
-- the reader that cannot apply the floor, since it opens read-only and a store
-- written before the constraint may still carry a negative count.
SELECT hash FROM objects WHERE refcount <= 0;

-- name: delete_garbage_objects
DELETE FROM objects WHERE refcount <= 0;

-- name: release_pins
-- Release one reference from each of :hashes (a JSON array): the set-based form
-- of adjust_refcount at -1, for a caller settling many at once (a purge sweeping
-- retained items releases each row's body and its conflict body).
--
-- A hash listed twice releases twice, which is what makes it the same operation
-- as the per-hash loop it replaces. Expressing a set operation as one point
-- update per element costs a hundred thousand statements inside one transaction
-- on a fifty-thousand-item purge.
UPDATE objects SET refcount = refcount -
  (SELECT count(*) FROM json_each(:hashes) WHERE value = objects.hash)
WHERE hash IN (SELECT value FROM json_each(:hashes));
