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
SELECT link_id, object_hash FROM items
WHERE object_hash IS NOT NULL
  AND link_id IN (SELECT value FROM json_each(:links));

-- name: recompute_refcounts
-- Recompute every object's refcount from the pointers that pin it: an item's
-- shared or conflict body, a source's base, or a pending queue action's body
-- (SPEC.md §15). O(items+bindings+queue), run once at the end of a write batch.
UPDATE objects SET refcount =
    (SELECT count(*) FROM items i
     WHERE i.object_hash = objects.hash OR i.conflict_object = objects.hash)
  + (SELECT count(*) FROM bindings b WHERE b.base_object = objects.hash)
  + (SELECT count(*) FROM queue q WHERE q.object_hash = objects.hash);

-- name: adjust_refcount
-- Adjust one object's refcount by the net change in pointers a batch made to
-- it (SPEC.md §14): the O(changes) alternative to recompute_refcounts, for an
-- implementation that diffs its writes. Preserves the same §5 invariant.
UPDATE objects SET refcount = refcount + :delta WHERE hash = :hash;

-- name: list_garbage_objects
-- Objects no item/binding pins; blob files unlinked before the rows go. The
-- predicate is `<= 0` rather than `= 0` so a refcount driven negative by a
-- double release is still swept rather than leaked for good, and it matches the
-- partial index objects_garbage exactly, so neither statement scans the table.
SELECT hash FROM objects WHERE refcount <= 0;

-- name: delete_garbage_objects
DELETE FROM objects WHERE refcount <= 0;
