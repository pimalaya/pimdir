-- The addresses of a collection's items, in document order within each role:
-- the diff's read over all of it (§4.5), load_addresses_by_link's for a batch.
SELECT link_id, role, position, address, name FROM item_address
WHERE collection = :collection
ORDER BY link_id, role, position;
