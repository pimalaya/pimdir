SELECT seq, link_id, flags, object_hash, sort_key, level FROM items
WHERE collection = :collection AND seq = :seq AND deleted = 0;
