-- pimdir bindings: one source's binding of an item, its handle there, the
-- three-way-merge base (the last state agreed with that source), and whether
-- that source's own sync is stuck on an unresolved content conflict.
--
-- Canonical reference statements servicing the store operations (SPEC.md §14).
-- An implementation SHOULD use them verbatim and MAY substitute an equivalent
-- that preserves the same invariants (SPEC.md §7). Column encodings are in
-- SPEC.md §13. Named parameters use `:name`.

-- name: load_bindings
-- Every per-source binding of a collection, attached to its item by link id.
SELECT link_id, source, handle, base_flags, base_object, base_revision,
       conflicted, conflict_revision
FROM bindings WHERE collection = :collection;

-- name: load_bindings_by_link
-- The same rows, narrowed to the link ids one write batch touches: the binding
-- half of load_items_by_link (queries/items.sql).
SELECT link_id, source, handle, base_flags, base_object, base_revision,
       conflicted, conflict_revision
FROM bindings WHERE collection = :collection
  AND link_id IN (SELECT value FROM json_each(:links));

-- name: insert_binding
INSERT INTO bindings(collection, link_id, source, handle, base_flags, base_object,
                     base_revision, conflicted, conflict_revision)
VALUES(:collection, :link_id, :source, :handle, :base_flags, :base_object,
       :base_revision, :conflicted, :conflict_revision);

-- The client read surface (SPEC.md §14.1).

-- name: list_sources
-- The distinct source names the store has synced, across every collection, so
-- a consumer can discover which source to attribute its writes to. Read from
-- bindings rather than sources: a source appears here as soon as it holds one
-- item, without waiting for a checkpoint row.
SELECT DISTINCT source FROM bindings ORDER BY source;

-- name: link_for_handle
-- The link id one source's handle is bound to. A write batch that drops a
-- placement names a handle, while the shared item it belongs to is keyed by
-- link id, so folding that drop in needs this resolution first. Served by the
-- bindings_by_handle index, so it is a seek: answering it by loading the
-- collection instead is what makes a one-row write cost a whole-mailbox read
-- (SPEC.md §14).
SELECT link_id FROM bindings
WHERE collection = :collection AND source = :source AND handle = :handle;
