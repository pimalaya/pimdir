-- The diff writer's row update (§14); the trigger stamps it only when a
-- column moved. Each body by its hash, written as insert_item writes it.
UPDATE items SET flags_known = :flags_known, marks = :marks,
       object = CASE WHEN :object_hash IS NULL THEN NULL ELSE coalesce((SELECT id FROM objects WHERE hash = :object_hash), 0) END,
       sort_key = :sort_key, level = :level, deleted = :deleted, conflicted = :conflicted,
       conflict_object = CASE WHEN :conflict_object IS NULL THEN NULL ELSE coalesce((SELECT id FROM objects WHERE hash = :conflict_object), 0) END
WHERE collection = :collection AND link_id = :link_id;
