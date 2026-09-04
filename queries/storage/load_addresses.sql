-- One item's people, in document order within each role.
SELECT role, position, address, name FROM item_address
WHERE collection = :collection AND link_id = :link_id
ORDER BY role, position;
