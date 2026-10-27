-- The task rows holding a body, store-wide, live or not, for a backfill
-- that re-derives task_summary columns from the bodies (§6): a keyset page
-- on the key (collection, link_id), a NULL :after_collection the first
-- page.
SELECT i.collection, i.link_id, i.seq, i.object_hash
FROM task_summary t JOIN items i ON i.collection = t.collection AND i.link_id = t.link_id
WHERE i.object_hash IS NOT NULL
  AND (:after_collection IS NULL OR (t.collection, t.link_id) > (:after_collection, :after_link_id))
ORDER BY t.collection, t.link_id LIMIT :limit;
