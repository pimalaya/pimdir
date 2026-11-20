-- The pending moves and copies whose target is :collection, for a reader
-- overlaying what they bring into it (§15.4). The rows queued on the item in
-- the collection it leaves are that collection's load_pending_actions.
SELECT id, created_at, producer, collection, action, payload, object_hash, attempts
FROM queue
WHERE target_collection = :collection AND error IS NULL AND action IN ('move', 'copy')
ORDER BY id;
