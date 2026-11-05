-- A keyset page in the kind's own ascending order: A to Z for contacts,
-- earliest first for mail and calendars. The cursor is a pair because a sort
-- key is not unique; `seq` breaks the tie and, being unique per collection,
-- makes the page total. The empty string with seq 0 starts from the beginning.
SELECT seq, link_id,
       CASE WHEN items.flags_known = 1
            THEN trim(CASE WHEN items.marks & 1 THEN '\Seen ' ELSE '' END
                   || CASE WHEN items.marks & 2 THEN '\Answered ' ELSE '' END
                   || CASE WHEN items.marks & 4 THEN '\Flagged ' ELSE '' END
                   || CASE WHEN items.marks & 8 THEN '\Draft ' ELSE '' END
                   || CASE WHEN items.marks & 16 THEN '\Deleted ' ELSE '' END
                   || coalesce((SELECT group_concat(f.flag, ' ') FROM placement_flag f WHERE f.item = items.id), '')) END AS flags,
       object_hash, sort_key, level FROM items
WHERE collection = :collection AND deleted = 0
  AND (sort_key, seq) > (:after_key, :after_seq)
ORDER BY sort_key, seq LIMIT :limit;
