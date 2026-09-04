-- Narrowed to the link ids one write batch touches: the binding half of
-- load_items_by_link.
SELECT link_id, source, handle, base_flags, base_object, base_revision,
       base_present, conflicted, conflict_revision, conflict_object, shared_object
FROM bindings WHERE collection = :collection
  AND link_id IN (SELECT value FROM json_each(:links));
