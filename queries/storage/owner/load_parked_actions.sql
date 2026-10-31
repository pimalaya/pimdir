SELECT id, created_at, producer, collection, action, payload, target_collection, attempts, error
FROM queue WHERE error IS NOT NULL ORDER BY id;
