-- The addresses of the link ids in the `links` slot, in document order within
-- each role, a seek per id: what the diff of one write batch reads (§14);
-- load_addresses_by_collection reads all of a collection's.
SELECT link_id, role, position, address, name FROM item_address
WHERE collection = :collection
  AND link_id IN (SELECT value FROM temp.param WHERE slot = 'links')
ORDER BY link_id, role, position;
