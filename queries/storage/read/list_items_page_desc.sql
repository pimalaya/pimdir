-- The same page descending; a NULL cursor is the first page, so a caller
-- never invents a key above every representable one.
SELECT seq, link_id,
       CASE WHEN items.flags_known = 1
            THEN coalesce((SELECT group_concat(f.flag, ' ') FROM placement_flag f
                           WHERE f.collection = items.collection AND f.link_id = items.link_id), '') END AS flags,
       object_hash, sort_key, level FROM items
WHERE collection = :collection AND deleted = 0
  AND (:after_key IS NULL OR (sort_key, seq) < (:after_key, :after_seq))
ORDER BY sort_key DESC, seq DESC LIMIT :limit;
