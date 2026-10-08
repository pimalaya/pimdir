-- Where this source holds a pending create of the identity in another
-- collection, a binding with no base: the destination a Tombstone placement
-- carries, so its remove is a relocation (SYNC.md §3). The create is keyed by
-- the identity or, staged beside a live holder, by the identity minted over the
-- provisional handle it derives, the bare key first; its handle tells which.
-- The counterpart of origin_for_link, read from the same rows.
SELECT collection, handle FROM bindings
WHERE (link_id = :link_id OR link_id = 'dup:' || :link_id || '#' || char(1) || :link_id)
  AND source = :source AND collection != :collection AND base_present = 0
ORDER BY link_id != :link_id, collection LIMIT 1;
