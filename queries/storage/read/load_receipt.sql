-- What an applied queue row or a performed intent became (§15.4, §15.5): the
-- collection and the seq of the item the row acted on or created, or an intent
-- left when its performer knew it; load_receipt_refusals reads the refusals
-- standing there. A NULL collection reads "its collection is gone": the row
-- was applied, and the collection it was queued on deleted since. No row, and
-- none in the queue, means the row was withdrawn, or applied before its
-- receipt was pruned.
SELECT applied_at, collection, seq FROM receipts WHERE id = :id;
