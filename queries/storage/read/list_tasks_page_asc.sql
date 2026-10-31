-- A LEFT JOIN: an item with no summary row (Annex A.3) still lists.
-- Soonest due first (§9.3, Annex A.4).
SELECT i.seq, i.link_id,
       CASE WHEN i.flags_known = 1
            THEN coalesce((SELECT group_concat(f.flag, ' ') FROM placement_flag f
                           WHERE f.collection = i.collection AND f.link_id = i.link_id), '') END AS flags,
       i.object_hash, i.sort_key, i.level,
       s.uid, s.summary, s.dtstart, s.dtstart_tzid, s.dtstart_value,
       s.due, s.due_tzid, s.due_value, s.status, s.completed, s.percent, s.recurring, s.until,
       s.priority, s.parent, s.mid, s.created
FROM items i LEFT JOIN task_summary s ON s.collection = i.collection AND s.link_id = i.link_id
WHERE i.collection = :collection AND i.deleted = 0
  AND (i.sort_key, i.seq) > (:after_key, :after_seq)
ORDER BY i.sort_key, i.seq LIMIT :limit;
