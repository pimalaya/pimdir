-- A keyset page in link-id order, riding the primary key with no extra index;
-- NULL is the first page, as the empty string is, a link_id never being
-- empty. That order means nothing to a reader: it is the page for a sweep
-- that must see every item exactly once, and a listing wants a sort-key page
-- below.
SELECT seq, link_id,
       CASE WHEN items.flags_known = 1
            THEN trim(CASE WHEN items.marks & 1 THEN '\Seen ' ELSE '' END
                   || CASE WHEN items.marks & 2 THEN '\Answered ' ELSE '' END
                   || CASE WHEN items.marks & 4 THEN '\Flagged ' ELSE '' END
                   || CASE WHEN items.marks & 8 THEN '\Draft ' ELSE '' END
                   || CASE WHEN items.marks & 16 THEN '\Deleted ' ELSE '' END
                   || coalesce((SELECT group_concat(f.flag, ' ') FROM placement_flag f WHERE f.item = items.id), '')) END AS flags,
       object_hash, sort_key, level FROM items
WHERE collection = :collection AND deleted = 0 AND link_id > coalesce(:after, '')
ORDER BY link_id LIMIT :limit;
