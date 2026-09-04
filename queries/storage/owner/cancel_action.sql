-- Removal by request rather than by application (§15.5): a queued item
-- withdrawn, or an intent acknowledged by the process that carried it out. It
-- releases the row's object_hash pin, so it MUST run in one transaction with
-- the refcount settle (§5, §14).
DELETE FROM queue WHERE id = :id;
