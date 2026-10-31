SELECT seq, link_id,
       CASE WHEN items.flags_known = 1
            THEN coalesce((SELECT group_concat(f.flag, ' ') FROM placement_flag f
                           WHERE f.collection = items.collection AND f.link_id = items.link_id), '') END AS flags,
       object_hash, sort_key, level FROM items
WHERE collection = :collection AND seq = :seq AND deleted = 0;
