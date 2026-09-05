-- The items waiting for a cross-source decision across one account's
-- collections (§10): the shared body kept and the diverging one recorded, so
-- a resolver reads both from the store. Rides items_conflicted, empty at rest.
SELECT i.collection, i.link_id, i.seq, i.object_hash, i.conflict_object
FROM items i JOIN collections c ON c.id = i.collection
WHERE i.conflicted = 1 AND c.account IS :account
ORDER BY i.collection, i.seq;
