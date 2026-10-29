-- The tombstones of a collection whose remove is held (§15.3, SYNC.md §5): an
-- add superseded them, and the item it created is live and still a pending
-- create of a source syncing its collection, a binding with no base or a
-- source binding nothing of it while it holds a body (SYNC.md §3). A create
-- accepted, withdrawn or purged releases the hold.
SELECT s.link_id
FROM supersessions s
JOIN items t ON t.collection = s.collection AND t.link_id = s.link_id
JOIN items n ON n.collection = s.by_collection AND n.link_id = s.by_link_id
WHERE s.collection = :collection AND t.deleted = 1 AND n.deleted = 0
  AND (EXISTS (SELECT 1 FROM bindings b
               WHERE b.collection = n.collection AND b.link_id = n.link_id
                 AND b.base_present = 0)
       OR (n.object_hash IS NOT NULL
           AND EXISTS (SELECT 1
                       FROM (SELECT source FROM sources WHERE collection = n.collection
                             UNION
                             SELECT source FROM bindings WHERE collection = n.collection) c
                       WHERE NOT EXISTS (SELECT 1 FROM bindings b
                                         WHERE b.collection = n.collection
                                           AND b.link_id = n.link_id
                                           AND b.source = c.source))))
ORDER BY s.link_id;
