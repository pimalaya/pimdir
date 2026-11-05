INSERT INTO task_category(item, position, value)
VALUES((SELECT id FROM items WHERE collection = :collection AND link_id = :link_id), :position, :value);
