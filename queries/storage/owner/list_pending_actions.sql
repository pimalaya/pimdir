-- The owner's drain: every pending action store-wide in append order (§15.2),
-- riding queue_pending. Read outside any transaction; claim_action decides
-- whether a row is still this transaction's to apply.
SELECT id, created_at, producer, collection, action, payload, object_hash, attempts
FROM queue WHERE error IS NULL ORDER BY id;
