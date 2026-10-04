-- One queue row by the id enqueue_action answered, pending (error NULL) or
-- parked (§15.4). No row means the row was applied (load_receipt) or cancelled.
SELECT id, created_at, producer, collection, action, payload, attempts, error
FROM queue WHERE id = :id;
