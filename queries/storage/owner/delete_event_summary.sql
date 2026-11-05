DELETE FROM event_summary WHERE item = (SELECT id FROM items WHERE collection = :collection AND link_id = :link_id);
