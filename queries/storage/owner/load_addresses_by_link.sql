-- The addresses of the link ids in the `links` slot, in document order within
-- each role, a seek per id: what the diff of one write batch reads (§14);
-- load_addresses_by_collection reads all of a collection's.
SELECT i.link_id, a.role, a.position, a.address, a.name
FROM items i JOIN item_address a ON a.item = i.id
WHERE i.collection = :collection
  AND i.link_id IN (SELECT value FROM temp.param WHERE slot = 'links')
ORDER BY i.link_id, a.role, a.position;
