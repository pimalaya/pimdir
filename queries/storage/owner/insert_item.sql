-- The stamp is the trigger's (§4.5); a writer never binds it.
INSERT INTO items(collection, link_id, seq, flags, object_hash, sort_key, level, deleted, conflicted, conflict_object)
VALUES(:collection, :link_id, :seq, :flags, :object_hash, :sort_key, :level, :deleted, :conflicted, :conflict_object);
