-- The store's feed, joined to what the index needs to fold a row: its
-- collection's kind and account, and whether it holds a body now.
SELECT i.collection, i.link_id, i.seq, i.object_hash, i.flags, i.deleted, i.retained_at, c.kind, c.account
FROM store.items i JOIN store.collections c ON c.id = i.collection
WHERE i.changed > :since ORDER BY i.changed LIMIT :limit;
