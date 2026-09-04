-- The trash listing, and the only read that returns retained items. :after is
-- the exclusive lower bound on `seq`, 0 starting from the beginning since seq
-- is handed out from 1: the cursor is the public id a reader already speaks
-- (§9.1), unlike the sweep page above, and it rides items_retained, which leads
-- with seq for this read. The size comes from the object the row still pins.
SELECT i.seq, i.link_id, i.flags, i.object_hash, i.sort_key, i.level,
       i.retained_at, i.retained_by, o.size
FROM items i LEFT JOIN objects o ON o.hash = i.object_hash
WHERE i.collection = :collection AND i.retained_at IS NOT NULL AND i.seq > :after
ORDER BY i.seq LIMIT :limit;
