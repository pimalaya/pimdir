-- The placements whose body the indexer could not read (§4), as
-- load_changed_items answers a row of the feed, so a pass folds them again
-- whether or not the store stamped them again, a body refetched under the
-- same name included. A placement the store no longer holds answers nothing
-- here: the feed or the key reconciliation drops it. Read from missing
-- first, so the few rows it holds seek the store rather than its feed.
SELECT i.collection, i.link_id, i.seq, i.object_hash,
       CASE WHEN i.flags_known = 1
            THEN trim(CASE WHEN i.marks & 1 THEN '\Seen ' ELSE '' END
                   || CASE WHEN i.marks & 2 THEN '\Answered ' ELSE '' END
                   || CASE WHEN i.marks & 4 THEN '\Flagged ' ELSE '' END
                   || CASE WHEN i.marks & 8 THEN '\Draft ' ELSE '' END
                   || CASE WHEN i.marks & 16 THEN '\Deleted ' ELSE '' END
                   || coalesce((SELECT group_concat(f.flag, ' ') FROM store.placement_flag f WHERE f.item = i.id), '')) END AS flags,
       i.deleted, i.retained_at, c.kind, c.account, i.changed
FROM missing m
CROSS JOIN store.items i ON i.collection = m.collection AND i.seq = m.seq
JOIN store.collections c ON c.id = i.collection
ORDER BY i.changed;
