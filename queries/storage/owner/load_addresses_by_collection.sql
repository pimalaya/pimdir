-- The addresses of a collection's items, in document order within each role:
-- the diff's read over all of it (§4.5), load_addresses_by_link's for a batch.
SELECT i.link_id, a.role, a.position, a.address, a.name
FROM items i JOIN item_address a ON a.item = i.id
WHERE i.collection = :collection
ORDER BY i.link_id, a.role, a.position;
