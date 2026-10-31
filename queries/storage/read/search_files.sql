-- Files of a set of collections whose name matches :pattern, on
-- search_contacts's terms.
SELECT i.collection, i.seq, i.link_id,
       CASE WHEN i.flags_known = 1
            THEN coalesce((SELECT group_concat(f.flag, ' ') FROM placement_flag f
                           WHERE f.collection = i.collection AND f.link_id = i.link_id), '') END AS flags,
       i.object_hash, i.sort_key, i.level,
       s.name, s.media_type, s.size, s.part
FROM items i JOIN file_summary s ON s.collection = i.collection AND s.link_id = i.link_id
WHERE i.collection IN (SELECT value FROM temp.param WHERE slot = 'collections') AND i.deleted = 0
  AND s.name LIKE :pattern ESCAPE '\'
  AND (:after_key IS NULL
       OR (i.sort_key, i.seq, i.collection) > (:after_key, :after_seq, :after_collection))
ORDER BY i.sort_key, i.seq, i.collection LIMIT :limit;
