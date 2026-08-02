-- pimdir bindings: one source's binding of an item, its handle there and the
-- three-way-merge base (the last state agreed with that source).
--
-- Canonical reference statements servicing the store operations (SPEC.md §12).
-- An implementation SHOULD use them verbatim and MAY substitute an equivalent
-- that preserves the same invariants (SPEC.md §8). Column encodings are in
-- SPEC.md §11. Named parameters use `:name`.

-- name: load_bindings
-- Every per-source binding of a collection, attached to its item by link id.
SELECT link_id, source, handle, base_flags, base_object, base_revision
FROM bindings WHERE collection = :collection;

-- name: insert_binding
INSERT INTO bindings(collection, link_id, source, handle, base_flags, base_object, base_revision)
VALUES(:collection, :link_id, :source, :handle, :base_flags, :base_object, :base_revision);
