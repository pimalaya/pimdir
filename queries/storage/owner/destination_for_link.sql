-- Where this source holds a pending create of the identity in another
-- collection, a binding with no base, or a delivered one, based under its
-- provisional handle (SYNC.md §2): the destination a Tombstone placement
-- carries, so its remove is a relocation (SYNC.md §3), which a delivery
-- recorded before the relocation left still offers. The create is keyed by
-- the identity or, staged beside a live holder, by the identity minted over the
-- provisional handle it derives, the bare key first; its handle tells which.
-- The counterpart of origin_for_link, read from the same rows, both keys a
-- seek on items_by_link, then the binding by its key.
SELECT b.collection, b.handle FROM items i JOIN bindings b ON b.item = i.id
WHERE (i.link_id = :link_id OR i.link_id = 'dup:' || :link_id || '#' || char(1) || :link_id)
  AND b.source = :source AND b.collection != :collection
  AND (b.base_present = 0 OR substr(b.handle, 1, 1) = char(1))
ORDER BY i.link_id != :link_id, b.collection LIMIT 1;
