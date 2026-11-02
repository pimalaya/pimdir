-- The same page descending; a NULL cursor is the first page, so a caller
-- never invents a key above every representable one. The cursor is coalesced
-- to the empty blob, which sorts above every text, rather than tested for
-- NULL, so it stays the seek on items_by_sort (§9.3).
SELECT seq, link_id,
       CASE WHEN items.flags_known = 1
            THEN coalesce((SELECT group_concat(f.flag, ' ') FROM placement_flag f
                           WHERE f.collection = items.collection AND f.link_id = items.link_id), '') END AS flags,
       object_hash, sort_key, level FROM items
WHERE collection = :collection AND deleted = 0
  AND (sort_key, seq) < (coalesce(:after_key, x''), coalesce(:after_seq, 0))
ORDER BY sort_key DESC, seq DESC LIMIT :limit;
