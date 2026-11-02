-- Files of a set of collections whose name matches :pattern, on
-- search_contacts's terms.
SELECT i.collection, i.seq, i.link_id,
       CASE WHEN i.flags_known = 1
            THEN coalesce((SELECT group_concat(f.flag, ' ') FROM placement_flag f
                           WHERE f.collection = i.collection AND f.link_id = i.link_id), '') END AS flags,
       i.object_hash, i.sort_key, i.level,
       s.name, s.media_type, s.size, s.part
FROM (SELECT DISTINCT value AS id FROM temp.param WHERE slot = 'collections') p
JOIN items i ON i.rowid IN (
  SELECT x.rowid FROM items x
  WHERE x.collection = p.id AND x.deleted = 0
    AND (x.sort_key, x.seq) >= (coalesce(:after_key, ''), coalesce(:after_seq, 0))
    AND (x.sort_key, x.seq, x.collection)
        > (coalesce(:after_key, ''), coalesce(:after_seq, 0), coalesce(:after_collection, ''))
    AND EXISTS (SELECT 1 FROM file_summary n
                WHERE n.collection = x.collection AND n.link_id = x.link_id
                  AND n.name LIKE :pattern ESCAPE '\')
  ORDER BY x.sort_key, x.seq LIMIT :limit)
JOIN file_summary s ON s.collection = i.collection AND s.link_id = i.link_id
ORDER BY i.sort_key, i.seq, i.collection LIMIT :limit;
