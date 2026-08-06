-- pimdir objects: the content-addressed body index and its reference counting.
-- The bytes live in blob files (SPEC.md §5); these rows are the index + refcount.
--
-- Canonical reference statements servicing the store operations (SPEC.md §12).
-- An implementation SHOULD use them verbatim and MAY substitute an equivalent
-- that preserves the same invariants (SPEC.md §8). Column encodings are in
-- SPEC.md §11. Named parameters use `:name`.

-- name: store_object
-- Index an object (write-op StoreObject); its bytes go to the blob file
-- (SPEC.md §5); refcount is recomputed after the batch.
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
-- (SPEC.md §14). O(items+bindings+queue), run once at the end of a write batch.
UPDATE objects SET refcount =
    (SELECT count(*) FROM items i
     WHERE i.object_hash = objects.hash OR i.conflict_object = objects.hash)
  + (SELECT count(*) FROM bindings b WHERE b.base_object = objects.hash)
  + (SELECT count(*) FROM queue q WHERE q.object_hash = objects.hash);

-- name: list_garbage_objects
-- Objects no item/binding pins; blob files unlinked before the rows go.
SELECT hash FROM objects WHERE refcount = 0;

-- name: delete_garbage_objects
DELETE FROM objects WHERE refcount = 0;
