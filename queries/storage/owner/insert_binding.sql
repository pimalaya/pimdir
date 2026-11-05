INSERT INTO bindings(item, collection, source, handle, base_flags_known, base_marks,
                     base_object, base_revision, base_present, conflicted, conflict_revision,
                     conflict_object, shared_object)
VALUES((SELECT id FROM items WHERE collection = :collection AND link_id = :link_id), :collection, :source, :handle, :base_flags_known, :base_marks,
       :base_object, :base_revision, :base_present, :conflicted, :conflict_revision,
       :conflict_object, :shared_object);
