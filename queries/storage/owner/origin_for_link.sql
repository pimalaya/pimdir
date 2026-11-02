-- Where this source already binds an identity in another collection with the
-- body a copy intends: the origin a Created placement carries, so its push is
-- a server-side copy (SYNC.md §3). A create keyed by an identity minted over
-- the provisional handle it derives pairs with that identity, the bare key
-- first. NULL :object means any body. The minted form is dup:, the key, #,
-- U+0001 and the key again, so the key it names is cut out by its length and
-- both arms seek bindings_by_link, the exact test kept as the filter.
SELECT collection, handle FROM bindings
WHERE link_id IN (:link_id, CASE WHEN :link_id GLOB 'dup:*'
                                 THEN substr(:link_id, 5, (length(:link_id) - 6) / 2) END)
  AND (link_id = :link_id OR 'dup:' || link_id || '#' || char(1) || link_id = :link_id)
  AND source = :source AND collection != :collection
  AND base_present = 1 AND (:object IS NULL OR base_object = :object)
ORDER BY link_id != :link_id, collection LIMIT 1;
