-- One hit's presentation row (§8), joined out of the store.
SELECT i.collection, c.account, c.kind, i.seq, i.link_id, i.flags, i.object_hash, i.sort_key, i.level
FROM store.items i JOIN store.collections c ON c.id = i.collection
WHERE i.collection = :collection AND i.seq = :seq AND i.deleted = 0;
