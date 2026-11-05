-- Retained items excluded: the sync seam sees live items only, and hiding them
-- here is what keeps one from being re-derived on a later sync (§11).
-- `sort_key` rides along although the sync layer has no use for it: a write
-- carries it back unchanged unless it restates it (§9.3).
SELECT link_id,
       CASE WHEN items.flags_known = 1
            THEN trim(CASE WHEN items.marks & 1 THEN '\Seen ' ELSE '' END
                   || CASE WHEN items.marks & 2 THEN '\Answered ' ELSE '' END
                   || CASE WHEN items.marks & 4 THEN '\Flagged ' ELSE '' END
                   || CASE WHEN items.marks & 8 THEN '\Draft ' ELSE '' END
                   || CASE WHEN items.marks & 16 THEN '\Deleted ' ELSE '' END
                   || coalesce((SELECT group_concat(f.flag, ' ') FROM placement_flag f WHERE f.item = items.id), '')) END AS flags,
       object_hash, sort_key, level, deleted, conflicted, conflict_object
FROM items WHERE collection = :collection AND retained_at IS NULL;
