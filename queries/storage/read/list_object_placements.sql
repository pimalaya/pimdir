-- The dedup axis rather than the identity one (§9), so this finds the same
-- message delivered to two accounts even when the servers rewrote its link id.
SELECT i.collection, c.account, i.seq, i.link_id,
       CASE WHEN i.flags_known = 1
            THEN trim(CASE WHEN i.marks & 1 THEN '\Seen ' ELSE '' END
                   || CASE WHEN i.marks & 2 THEN '\Answered ' ELSE '' END
                   || CASE WHEN i.marks & 4 THEN '\Flagged ' ELSE '' END
                   || CASE WHEN i.marks & 8 THEN '\Draft ' ELSE '' END
                   || CASE WHEN i.marks & 16 THEN '\Deleted ' ELSE '' END
                   || coalesce((SELECT group_concat(f.flag, ' ') FROM placement_flag f WHERE f.item = i.id), '')) END AS flags,
       i.level
FROM items i JOIN collections c ON c.id = i.collection
WHERE i.object_hash = :hash AND i.deleted = 0 AND i.retained_at IS NULL
ORDER BY c.account IS NULL, c.account, i.collection;
