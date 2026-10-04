-- What an applied queue row or a performed intent became (§15.4, §15.5): the
-- collection and the seq of the item an `add` created, or an intent left when
-- its performer knew it. No row, and none in the queue, means the row was
-- withdrawn, or applied before its receipt was pruned.
SELECT applied_at, collection, seq FROM receipts WHERE id = :id;
