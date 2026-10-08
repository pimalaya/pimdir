-- Where this source already binds an identity in another collection with the
-- body a copy intends: the origin a Created placement carries, so its push is
-- a server-side copy (SYNC.md §3). A create keyed by an identity minted over
-- the provisional handle it derives pairs with that identity, the bare key
-- first. NULL :object means any body.
SELECT collection, handle FROM bindings
WHERE (link_id = :link_id OR 'dup:' || link_id || '#' || char(1) || link_id = :link_id)
  AND source = :source AND collection != :collection
  AND base_present = 1 AND (:object IS NULL OR base_object = :object)
ORDER BY link_id != :link_id, collection LIMIT 1;
