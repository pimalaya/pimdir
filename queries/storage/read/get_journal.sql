-- A LEFT JOIN: an item with no summary row (Annex A.3) still lists.
SELECT i.seq, i.link_id,
       CASE WHEN i.flags_known = 1
            THEN coalesce((SELECT group_concat(f.flag, ' ') FROM placement_flag f
                           WHERE f.collection = i.collection AND f.link_id = i.link_id), '') END AS flags,
       i.object_hash, i.sort_key, i.level,
       s.uid, s.summary, s.dtstart, s.dtstart_tzid, s.dtstart_value
FROM items i LEFT JOIN journal_summary s ON s.collection = i.collection AND s.link_id = i.link_id
WHERE i.collection = :collection AND i.seq = :seq AND i.deleted = 0;
