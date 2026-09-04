-- Removal by request rather than by application (§15.5): a queued item
-- withdrawn, or an intent acknowledged by the process that carried it out. It
-- returns the row's object_hash pin, released in the same transaction (§5, §14).
DELETE FROM queue WHERE id = :id RETURNING object_hash;
