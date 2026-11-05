-- The members a collection's pending creates may be moved from (§15.3, SYNC.md
-- §4): for each live item of :collection that superseded an item of its own
-- identity in another collection, while :source holds no base for it here and
-- binds the superseded item there with a base, that binding's collection,
-- handle and revision. A connector moving members server-side delivers the
-- create by moving that member, so the identity never lives twice on the
-- server. A superseding item of another identity is a plain create.
SELECT n.link_id, t.collection, b.handle, b.base_revision
FROM supersessions s
JOIN items n ON n.id = s.by_item
JOIN items t ON t.id = s.item
JOIN bindings b ON b.item = s.item AND b.source = :source AND b.base_present = 1
WHERE n.collection = :collection AND t.link_id = n.link_id
  AND n.deleted = 0 AND t.deleted = 1
  AND NOT EXISTS (SELECT 1 FROM bindings h
                  WHERE h.item = n.id AND h.source = :source AND h.base_present = 1)
ORDER BY n.link_id;
