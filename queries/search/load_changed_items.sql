-- The store's feed, joined to what the index needs to fold a row: its
-- collection's kind and account, whether it holds a body now, and its stamp,
-- which a batch may record as the cursor it reached (§4).
SELECT i.collection, i.link_id, i.seq, i.object_hash,
       CASE WHEN i.flags_known = 1
            THEN trim(CASE WHEN i.marks & 1 THEN '\Seen ' ELSE '' END
                   || CASE WHEN i.marks & 2 THEN '\Answered ' ELSE '' END
                   || CASE WHEN i.marks & 4 THEN '\Flagged ' ELSE '' END
                   || CASE WHEN i.marks & 8 THEN '\Draft ' ELSE '' END
                   || CASE WHEN i.marks & 16 THEN '\Deleted ' ELSE '' END
                   || coalesce((SELECT group_concat(f.flag, ' ') FROM store.placement_flag f WHERE f.item = i.id), '')) END AS flags,
       i.deleted, i.retained_at, c.kind, c.account, i.changed
FROM store.items i JOIN store.collections c ON c.id = i.collection
WHERE i.changed > :since ORDER BY i.changed LIMIT :limit;
