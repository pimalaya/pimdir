-- The placements whose body the indexer could not read (§4), as
-- load_changed_items answers a row of the feed, so a pass folds them again
-- whether or not the store stamped them again, a body refetched under the
-- same name included. A placement the store no longer holds answers nothing
-- here: the feed or the key reconciliation drops it. Read from missing
-- first, so the few rows it holds seek the store rather than its feed.
SELECT i.collection, i.link_id, i.seq, i.object_hash,
       CASE WHEN i.flags_known = 1
            THEN coalesce((SELECT group_concat(f.flag, ' ') FROM store.placement_flag f
                           WHERE f.collection = i.collection AND f.link_id = i.link_id), '') END AS flags,
       i.deleted, i.retained_at, c.kind, c.account, i.changed
FROM missing m
CROSS JOIN store.items i ON i.collection = m.collection AND i.seq = m.seq
JOIN store.collections c ON c.id = i.collection
ORDER BY i.changed;
