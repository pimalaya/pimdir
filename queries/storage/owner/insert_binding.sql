-- Each body by its hash, written as insert_item writes it (§4.4).
INSERT INTO bindings(item, collection, source, handle, base_flags_known, base_marks,
                     base_object, base_revision, base_present, conflicted, conflict_revision,
                     conflict_object, shared_object, server_object_id)
VALUES((SELECT id FROM items WHERE collection = :collection AND link_id = :link_id), :collection, :source, :handle, :base_flags_known, :base_marks,
       CASE WHEN :base_object IS NULL THEN NULL ELSE coalesce((SELECT id FROM objects WHERE hash = :base_object), 0) END,
       :base_revision, :base_present, :conflicted, :conflict_revision,
       CASE WHEN :conflict_object IS NULL THEN NULL ELSE coalesce((SELECT id FROM objects WHERE hash = :conflict_object), 0) END,
       CASE WHEN :shared_object IS NULL THEN NULL ELSE coalesce((SELECT id FROM objects WHERE hash = :shared_object), 0) END,
       :server_object_id);
