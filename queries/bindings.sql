-- pimdir bindings: one source's binding of an item, its handle there, the
-- three-way-merge base (the last state agreed with that source), and whether
-- that source's own sync is stuck on an unresolved content conflict.
--
-- Canonical reference statements servicing the store operations (SPEC.md §12).
-- An implementation SHOULD use them verbatim and MAY substitute an equivalent
-- that preserves the same invariants (SPEC.md §8). Column encodings are in
-- SPEC.md §11. Named parameters use `:name`.

-- name: load_bindings
-- Every per-source binding of a collection, attached to its item by link id.
SELECT link_id, source, handle, base_flags, base_object, base_revision,
       conflicted, conflict_revision
FROM bindings WHERE collection = :collection;

-- name: insert_binding
INSERT INTO bindings(collection, link_id, source, handle, base_flags, base_object,
                     base_revision, conflicted, conflict_revision)
VALUES(:collection, :link_id, :source, :handle, :base_flags, :base_object,
       :base_revision, :conflicted, :conflict_revision);

-- The client read surface (SPEC.md §12.1).

-- name: list_sources
-- The distinct source names the store has synced, across every collection, so
-- a consumer can discover which source to attribute its writes to. Read from
-- bindings rather than sources: a source appears here as soon as it holds one
-- item, without waiting for a checkpoint row.
SELECT DISTINCT source FROM bindings ORDER BY source;
