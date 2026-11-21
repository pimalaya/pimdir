-- The link ids of a collection's live items holding a body that a source
-- binds not (SYNC.md §3): its Created projections, offered to it as
-- propagation, which no binding of it names. A delta loads them by link
-- beside what it lists (SYNC.md §10). For a source syncing the collection
-- (a row of sources) they are among the items the lacking mark holds (STORAGE
-- §4.6), sought on items_lacking. A source no row names was never counted by
-- the mark, so for it the collection is walked: the walk is the inner loop
-- of a one-row guard that is empty while the row exists, so it never starts.
SELECT i.link_id FROM items i
WHERE i.collection = :collection AND i.lacks = 1
  AND EXISTS (SELECT 1 FROM sources s WHERE s.collection = :collection AND s.source = :source)
  AND NOT EXISTS (SELECT 1 FROM bindings b WHERE b.item = i.id AND b.source = :source)
UNION ALL
SELECT i.link_id
FROM (SELECT 1 WHERE NOT EXISTS (SELECT 1 FROM sources s
                                 WHERE s.collection = :collection AND s.source = :source)) AS unsynced
CROSS JOIN items i
WHERE i.collection = :collection AND i.deleted = 0 AND i.object IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM bindings b WHERE b.item = i.id AND b.source = :source)
ORDER BY link_id;
