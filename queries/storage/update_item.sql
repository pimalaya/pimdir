-- The diff writer's row update (§14); the trigger stamps it only when a
-- column moved.
UPDATE items SET flags = :flags, object_hash = :object_hash, sort_key = :sort_key,
       level = :level, deleted = :deleted, conflicted = :conflicted,
       conflict_object = :conflict_object
WHERE collection = :collection AND link_id = :link_id;
