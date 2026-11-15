-- The refusals standing on the item an applied queue row acted on (§15.4,
-- SYNC.md §5): per collection filing it and source binding it, the reason the
-- remote refused that source's push and when. The item is every row of the
-- receipt's seq in the account of the collection the row was queued on, so a
-- move reads the create it left in its target. No row: none stands, the
-- receipt names no item, or its collection is gone.
SELECT i.collection, b.source, b.refusal, b.refused_at
FROM receipts r
JOIN collections q ON q.id = r.collection
JOIN items i ON i.seq = r.seq
JOIN collections c ON c.id = i.collection AND c.account IS q.account
JOIN bindings b ON b.item = i.id
WHERE r.id = :id AND b.refusal IS NOT NULL
ORDER BY i.collection, b.source;
