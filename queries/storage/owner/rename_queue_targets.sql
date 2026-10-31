-- Runs beside rename_collection (§14): a pending move or copy names its
-- target, and a pending add the collection of the item it supersedes, in
-- target_collection, which no foreign key cascades.
UPDATE queue SET target_collection = :new_id
WHERE error IS NULL AND target_collection = :collection;
