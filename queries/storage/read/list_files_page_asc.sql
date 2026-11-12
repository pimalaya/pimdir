-- A LEFT JOIN: an item with no summary row still lists. A to Z on the
-- normalised name (Annex A.7).
SELECT i.seq, i.link_id,
       CASE WHEN i.flags_known = 1
            THEN trim(CASE WHEN i.marks & 1 THEN '\Seen ' ELSE '' END
                   || CASE WHEN i.marks & 2 THEN '\Answered ' ELSE '' END
                   || CASE WHEN i.marks & 4 THEN '\Flagged ' ELSE '' END
                   || CASE WHEN i.marks & 8 THEN '\Draft ' ELSE '' END
                   || CASE WHEN i.marks & 16 THEN '\Deleted ' ELSE '' END
                   || coalesce((SELECT group_concat(f.flag, ' ') FROM placement_flag f WHERE f.item = i.id), '')) END AS flags,
       i.object_hash, i.sort_key, i.level,
       s.name, s.media_type, s.size, s.part
FROM items i LEFT JOIN file_summary s ON s.item = i.id
WHERE i.collection = :collection AND i.deleted = 0
  AND (i.sort_key, i.seq) > (coalesce(:after_key, ''), coalesce(:after_seq, 0))
ORDER BY i.sort_key, i.seq LIMIT :limit;
