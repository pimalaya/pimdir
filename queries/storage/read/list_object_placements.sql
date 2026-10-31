-- The dedup axis rather than the identity one (§9), so this finds the same
-- message delivered to two accounts even when the servers rewrote its link id.
SELECT i.collection, c.account, i.seq, i.link_id,
       CASE WHEN i.flags_known = 1
            THEN coalesce((SELECT group_concat(f.flag, ' ') FROM placement_flag f
                           WHERE f.collection = i.collection AND f.link_id = i.link_id), '') END AS flags,
       i.level
FROM items i JOIN collections c ON c.id = i.collection
WHERE i.object_hash = :hash AND i.deleted = 0 AND i.retained_at IS NULL
ORDER BY c.account IS NULL, c.account, i.collection;
