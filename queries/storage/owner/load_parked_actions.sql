SELECT id, created_at, producer, collection, action, payload, attempts, error
FROM queue WHERE error IS NOT NULL ORDER BY id;
