INSERT INTO item_address(item, role, position, address, name)
VALUES((SELECT id FROM items WHERE collection = :collection AND link_id = :link_id), :role, :position, :address, :name);
