-- pimdir canonical storage operations (schema version 1).
--
-- The named, parameterised statements every implementation runs to service the
-- io-replica storage seam (SPEC.md §13). Canonical reference: an implementation
-- SHOULD use them verbatim and MAY substitute an equivalent that preserves the
-- same invariants (SPEC.md §8). Column encodings are in SPEC.md §12. Named
-- parameters use `:name`.
--
-- The store persists a per-collection hub — shared `items` plus a `binding` per
-- source. `load` for a source projects the items it holds (or should copy) into
-- placements; `write` folds a source's writes back. Loading and saving a
-- collection's hub is a load-all / replace-all of its items and bindings; a flag
-- change or add touches only the affected collection.

-- name: ensure_collection
-- Guarantee the FK target exists before a source, item or checkpoint write.
INSERT INTO collections(id, kind, name) VALUES(:collection, '', :collection)
ON CONFLICT(id) DO NOTHING;

-- name: set_conflict
UPDATE collections SET conflict = :conflict WHERE id = :collection;

-- name: load_conflict
SELECT conflict FROM collections WHERE id = :collection;

-- name: load_items
-- Every shared item of a collection.
SELECT link_id, flags, object_hash, meta, level, deleted, conflicted, conflict_object
FROM items WHERE collection = :collection;

-- name: load_bindings
-- Every per-source binding of a collection, attached to its item by link id.
SELECT link_id, source, handle, base_flags, base_object, base_revision
FROM bindings WHERE collection = :collection;

-- name: load_checkpoint
-- One source's sync cursor for a collection.
SELECT checkpoint FROM sources WHERE collection = :collection AND source = :source;

-- name: delete_items
-- Clears a collection's items before a hub save (bindings cascade).
DELETE FROM items WHERE collection = :collection;

-- name: insert_item
INSERT INTO items(collection, link_id, flags, object_hash, meta, level, deleted, conflicted, conflict_object)
VALUES(:collection, :link_id, :flags, :object_hash, :meta, :level, :deleted, :conflicted, :conflict_object);

-- name: insert_binding
INSERT INTO bindings(collection, link_id, source, handle, base_flags, base_object, base_revision)
VALUES(:collection, :link_id, :source, :handle, :base_flags, :base_object, :base_revision);

-- name: upsert_checkpoint
INSERT INTO sources(collection, source, checkpoint) VALUES(:collection, :source, :checkpoint)
ON CONFLICT(collection, source) DO UPDATE SET checkpoint = excluded.checkpoint;

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
-- Recompute every object's refcount from the item and binding pointers that pin
-- it (shared body, conflict body, or a source's base). O(items+bindings), run
-- once at the end of a write batch.
UPDATE objects SET refcount =
    (SELECT count(*) FROM items i
     WHERE i.object_hash = objects.hash OR i.conflict_object = objects.hash)
  + (SELECT count(*) FROM bindings b WHERE b.base_object = objects.hash);

-- name: list_garbage_objects
-- Objects no item/binding pins; blob files unlinked before the rows go.
SELECT hash FROM objects WHERE refcount = 0;

-- name: delete_garbage_objects
DELETE FROM objects WHERE refcount = 0;
