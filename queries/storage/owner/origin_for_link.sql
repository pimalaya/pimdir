-- Where this source already binds an identity in another collection with the
-- body a copy intends: the origin a Created placement carries, so its push is
-- a server-side copy (SYNC.md §3). NULL :object means any body.
SELECT collection, handle FROM bindings
WHERE link_id = :link_id AND source = :source AND collection != :collection
  AND base_present = 1 AND (:object IS NULL OR base_object = :object)
ORDER BY collection LIMIT 1;
