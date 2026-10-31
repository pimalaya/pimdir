-- A LEFT JOIN: an item with no summary row (Annex A.3) still lists.
-- Newest first, the usual mail listing; a NULL cursor is the first page.
SELECT i.seq, i.link_id,
       CASE WHEN i.flags_known = 1
            THEN coalesce((SELECT group_concat(f.flag, ' ') FROM placement_flag f
                           WHERE f.collection = i.collection AND f.link_id = i.link_id), '') END AS flags,
       i.object_hash, i.sort_key, i.level,
       s.message_id, s.subject, s.sender, s.sender_name, s.date, s.size, s.attachment
FROM items i LEFT JOIN mail_summary s ON s.collection = i.collection AND s.link_id = i.link_id
WHERE i.collection = :collection AND i.deleted = 0
  AND (:after_key IS NULL OR (i.sort_key, i.seq) < (:after_key, :after_seq))
ORDER BY i.sort_key DESC, i.seq DESC LIMIT :limit;
