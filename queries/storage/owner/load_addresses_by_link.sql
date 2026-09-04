-- The addresses of a collection's items, or of the link ids in :links when
-- bound, in document order within each role; the diff's read (§4.5).
SELECT link_id, role, position, address, name FROM item_address
WHERE collection = :collection
  AND (:links IS NULL OR link_id IN (SELECT value FROM json_each(:links)))
ORDER BY link_id, role, position;
