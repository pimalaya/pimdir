-- What an applied queue row became (§15.4): the collection and, for an `add`,
-- the seq of the item it created. No row, and none in the queue, means the row
-- was cancelled, or applied before its receipt was pruned.
SELECT applied_at, collection, seq FROM receipts WHERE id = :id;
