-- Where this source already binds an identity in another collection with the
-- body a copy intends: the origin a Created placement carries, so its push is
-- a server-side copy (SYNC.md §3). A create keyed by an identity minted over
-- the provisional handle it derives pairs with that identity, the bare key
-- first. NULL :object means any body. The minted form is dup:, the key, #,
-- U+0001 and the key again, so the key it names is cut out by its length and
-- both arms seek bindings_by_link, the exact test kept as the filter.
SELECT b.collection, b.handle FROM items i JOIN bindings b ON b.item = i.id
WHERE i.link_id IN (:link_id, CASE WHEN :link_id GLOB 'dup:*'
                                   THEN substr(:link_id, 5, (length(:link_id) - 6) / 2) END)
  AND (i.link_id = :link_id OR 'dup:' || i.link_id || '#' || char(1) || i.link_id = :link_id)
  AND b.source = :source AND b.collection != :collection
  AND b.base_present = 1 AND (:object IS NULL OR b.base_object = :object)
ORDER BY i.link_id != :link_id, b.collection LIMIT 1;
