-- Where this source holds a pending create of the identity in another
-- collection, a binding with no base: the destination a Tombstone placement
-- carries, so its remove is a relocation (SYNC.md §3). The counterpart of
-- origin_for_link, read from the same rows.
SELECT collection FROM bindings
WHERE link_id = :link_id AND source = :source AND collection != :collection
  AND base_present = 0
ORDER BY collection LIMIT 1;
