-- The mail rows holding a body, store-wide, live or not, for a backfill
-- that re-derives a column from the bodies (§6): a keyset page on the key
-- (collection, link_id), a NULL :after_collection the first page.
SELECT i.collection, i.link_id, i.seq, i.object_hash
FROM items i JOIN collections c ON c.id = i.collection AND c.kind = 'message/rfc822'
WHERE i.object_hash IS NOT NULL
  AND (:after_collection IS NULL OR (i.collection, i.link_id) > (:after_collection, :after_link_id))
ORDER BY i.collection, i.link_id LIMIT :limit;
