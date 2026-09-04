-- Re-projects the key of an item already stored, for a kind whose convention
-- arrived or changed after the write. Ordinary writes carry it in insert_item.
UPDATE items SET sort_key = :sort_key
WHERE collection = :collection AND link_id = :link_id;
