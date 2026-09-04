-- Runs FIRST in the transaction that applies the action, not last: the pending
-- rows are read outside any transaction, so a second owner holding the same
-- list would otherwise apply every one twice, and `add` and `copy` are not
-- idempotent. A claim that deletes nothing means another owner got there
-- first (§15.2).
DELETE FROM queue WHERE id = :id RETURNING id;
