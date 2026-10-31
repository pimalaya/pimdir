-- A LEFT JOIN: an item with no summary row (Annex A.3) still lists.
-- A to Z on the normalised name.
SELECT i.seq, i.link_id,
       CASE WHEN i.flags_known = 1
            THEN coalesce((SELECT group_concat(f.flag, ' ') FROM placement_flag f
                           WHERE f.collection = i.collection AND f.link_id = i.link_id), '') END AS flags,
       i.object_hash, i.sort_key, i.level,
       s.uid, s.fn, s.kind, s.org
FROM items i LEFT JOIN contact_summary s ON s.collection = i.collection AND s.link_id = i.link_id
WHERE i.collection = :collection AND i.deleted = 0
  AND (i.sort_key, i.seq) > (:after_key, :after_seq)
ORDER BY i.sort_key, i.seq LIMIT :limit;
