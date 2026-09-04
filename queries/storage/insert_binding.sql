INSERT INTO bindings(collection, link_id, source, handle, base_flags, base_object,
                     base_revision, base_present, conflicted, conflict_revision,
                     conflict_object, shared_object)
VALUES(:collection, :link_id, :source, :handle, :base_flags, :base_object,
       :base_revision, :base_present, :conflicted, :conflict_revision,
       :conflict_object, :shared_object);
