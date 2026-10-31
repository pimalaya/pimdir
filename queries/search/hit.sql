-- One hit's presentation row (§8), joined out of the store.
SELECT i.collection, c.account, c.kind, i.seq, i.link_id,
       CASE WHEN i.flags_known = 1
            THEN coalesce((SELECT group_concat(f.flag, ' ') FROM store.placement_flag f
                           WHERE f.collection = i.collection AND f.link_id = i.link_id), '') END AS flags,
       i.object_hash, i.sort_key, i.level
FROM store.items i JOIN store.collections c ON c.id = i.collection
WHERE i.collection = :collection AND i.seq = :seq AND i.deleted = 0;
