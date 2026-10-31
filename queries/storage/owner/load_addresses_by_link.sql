-- The addresses of a collection's items, or with :scoped 1 of the link ids in
-- the `links` slot, in document order within each role; the diff's read
-- (§4.5).
SELECT link_id, role, position, address, name FROM item_address
WHERE collection = :collection
  AND (:scoped = 0 OR link_id IN (SELECT value FROM temp.param WHERE slot = 'links'))
ORDER BY link_id, role, position;
