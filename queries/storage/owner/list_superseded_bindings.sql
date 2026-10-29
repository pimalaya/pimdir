-- The members a collection's pending creates may be moved from (§15.3, SYNC.md
-- §4): for each live item of :collection that superseded an item of its own
-- identity in another collection, while :source holds no base for it here and
-- binds the superseded item there with a base, that binding's collection,
-- handle and revision. A connector moving members server-side delivers the
-- create by moving that member, so the identity never lives twice on the
-- server. A superseding item of another identity is a plain create.
SELECT n.link_id, s.collection, b.handle, b.base_revision
FROM supersessions s
JOIN items n ON n.collection = s.by_collection AND n.link_id = s.by_link_id
JOIN items t ON t.collection = s.collection AND t.link_id = s.link_id
JOIN bindings b ON b.collection = s.collection AND b.link_id = s.link_id
    AND b.source = :source AND b.base_present = 1
WHERE s.by_collection = :collection AND s.link_id = s.by_link_id
  AND n.deleted = 0 AND t.deleted = 1
  AND NOT EXISTS (SELECT 1 FROM bindings h
                  WHERE h.collection = n.collection AND h.link_id = n.link_id
                    AND h.source = :source AND h.base_present = 1)
ORDER BY n.link_id;
