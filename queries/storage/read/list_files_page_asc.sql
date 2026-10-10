-- A LEFT JOIN: an item with no summary row still lists. A to Z on the
-- normalised name (Annex A.7).
SELECT i.seq, i.link_id, i.flags, i.object_hash, i.sort_key, i.level,
       s.name, s.media_type, s.size, s.part
FROM items i LEFT JOIN file_summary s ON s.collection = i.collection AND s.link_id = i.link_id
WHERE i.collection = :collection AND i.deleted = 0
  AND (i.sort_key, i.seq) > (:after_key, :after_seq)
ORDER BY i.sort_key, i.seq LIMIT :limit;
