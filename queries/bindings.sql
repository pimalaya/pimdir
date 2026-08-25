-- pimdir bindings: one source's binding of an item, its handle there, the
-- three-way-merge base, and whether that source's own sync is stuck on an
-- unresolved content conflict.
--
-- Reference statements for the store operations (SPEC.md §4.4, §14); column
-- encodings in §13, named parameters `:name`.

-- name: load_bindings
SELECT link_id, source, handle, base_flags, base_object, base_revision,
       base_present, conflicted, conflict_revision, ambiguous_handles
FROM bindings WHERE collection = :collection;

-- name: load_bindings_by_link
-- Narrowed to the link ids one write batch touches: the binding half of
-- load_items_by_link (queries/items.sql).
SELECT link_id, source, handle, base_flags, base_object, base_revision,
       base_present, conflicted, conflict_revision, ambiguous_handles
FROM bindings WHERE collection = :collection
  AND link_id IN (SELECT value FROM json_each(:links));

-- name: insert_binding
INSERT INTO bindings(collection, link_id, source, handle, base_flags, base_object,
                     base_revision, base_present, conflicted, conflict_revision,
                     ambiguous_handles)
VALUES(:collection, :link_id, :source, :handle, :base_flags, :base_object,
       :base_revision, :base_present, :conflicted, :conflict_revision,
       :ambiguous_handles);

-- name: update_binding
-- `handle` is deliberately absent: repointing it is how a source holding one
-- identity twice used to be destroyed, silently, at the write. The second copy
-- goes to `ambiguous_handles` instead, freezing the item until the source holds
-- the identity once again (§10); a legitimate rebind goes through the
-- handle-space rebuild.
UPDATE bindings SET base_flags = :base_flags, base_object = :base_object,
       base_revision = :base_revision, base_present = :base_present,
       conflicted = :conflicted, conflict_revision = :conflict_revision,
       ambiguous_handles = :ambiguous_handles
WHERE collection = :collection AND link_id = :link_id AND source = :source;

-- The client read surface (§14.1).

-- name: list_sources
-- Read from bindings rather than sources, so a source appears as soon as it
-- holds one item, without waiting for a checkpoint row.
SELECT DISTINCT source FROM bindings ORDER BY source;

-- name: link_for_handle
-- A write batch dropping a placement names a handle, while the shared item is
-- keyed by link id. Rides bindings_by_handle, so it is a seek: answering it by
-- loading the collection is what makes a one-row write cost a whole-mailbox
-- read (§14).
SELECT link_id FROM bindings
WHERE collection = :collection AND source = :source AND handle = :handle;
