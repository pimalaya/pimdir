-- The stamp is the trigger's (§4.5); a writer never binds it. A body is named
-- by its hash and written as its objects.id (§4.4): a hash no object row
-- holds resolves to 0, which the foreign key refuses.
INSERT INTO items(collection, link_id, seq, flags_known, marks, object, sort_key, level, deleted, conflicted, conflict_object)
VALUES(:collection, :link_id, :seq, :flags_known, :marks,
       CASE WHEN :object_hash IS NULL THEN NULL ELSE coalesce((SELECT id FROM objects WHERE hash = :object_hash), 0) END,
       :sort_key, :level, :deleted, :conflicted,
       CASE WHEN :conflict_object IS NULL THEN NULL ELSE coalesce((SELECT id FROM objects WHERE hash = :conflict_object), 0) END);
