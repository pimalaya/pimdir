-- The link ids of a collection's live items holding a body that a source
-- binds not (SYNC.md §3): its Created projections, offered to it as
-- propagation, which no binding of it names. A delta loads them by link
-- beside what it lists (SYNC.md §10).
SELECT i.link_id FROM items i
WHERE i.collection = :collection AND i.deleted = 0 AND i.object_hash IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM bindings b WHERE b.item = i.id AND b.source = :source)
ORDER BY i.link_id;
