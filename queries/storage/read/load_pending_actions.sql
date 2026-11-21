-- One collection's pending actions, for a reader overlaying them on what it
-- shows (§15.4). The owner's drain is list_pending_actions, store-wide.
SELECT id, created_at, producer, action, payload, target_collection, (SELECT o.hash FROM objects o WHERE o.id = queue.object) AS object_hash, attempts
FROM queue WHERE collection = :collection AND error IS NULL ORDER BY id;
