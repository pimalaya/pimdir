-- The tombstones of a collection whose remove is held (§15.3, SYNC.md §5): an
-- add superseded them, and the item it created is live and still a pending
-- create of a source syncing its collection, a binding with no base or a
-- source binding nothing of it while it holds a body (SYNC.md §3). A create
-- accepted, withdrawn or purged releases the hold. Read from supersessions,
-- as list_superseded_bindings is and for its reason.
SELECT t.link_id
FROM supersessions s
CROSS JOIN items t ON t.id = s.item
CROSS JOIN items n ON n.id = s.by_item
WHERE t.collection = :collection AND t.deleted = 1 AND n.deleted = 0
  AND (EXISTS (SELECT 1 FROM bindings b WHERE b.item = n.id AND b.base_present = 0)
       OR (n.object_hash IS NOT NULL
           AND EXISTS (SELECT 1
                       FROM (SELECT source FROM sources WHERE collection = n.collection
                             UNION
                             SELECT source FROM bindings WHERE collection = n.collection) c
                       WHERE NOT EXISTS (SELECT 1 FROM bindings b
                                         WHERE b.item = n.id AND b.source = c.source))))
ORDER BY t.link_id;
