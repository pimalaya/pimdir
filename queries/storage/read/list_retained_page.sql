-- The trash listing, and the only read that returns deleted rows: retained
-- ones, and tombstones still propagating to a source that holds them (§11).
-- :after is the exclusive lower bound on `seq`, 0 starting from the beginning
-- since seq is handed out from 1: the cursor is the public id a reader already
-- speaks (§9.1), and the read rides items_retained. A NULL retained_at marks
-- a row a source still binds. The size comes from the object the row pins.
SELECT i.seq, i.link_id,
       CASE WHEN i.flags_known = 1
            THEN trim(CASE WHEN i.marks & 1 THEN '\Seen ' ELSE '' END
                   || CASE WHEN i.marks & 2 THEN '\Answered ' ELSE '' END
                   || CASE WHEN i.marks & 4 THEN '\Flagged ' ELSE '' END
                   || CASE WHEN i.marks & 8 THEN '\Draft ' ELSE '' END
                   || CASE WHEN i.marks & 16 THEN '\Deleted ' ELSE '' END
                   || coalesce((SELECT group_concat(f.flag, ' ') FROM placement_flag f WHERE f.item = i.id), '')) END AS flags,
       i.object_hash, i.sort_key, i.level,
       i.retained_at, i.retained_by, o.size
FROM items i LEFT JOIN objects o ON o.hash = i.object_hash
WHERE i.collection = :collection AND i.deleted = 1 AND i.seq > :after
ORDER BY i.seq LIMIT :limit;
