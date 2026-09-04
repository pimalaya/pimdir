-- A LEFT JOIN: a probed item has a row and no summary yet.
-- Chronological on the first occurrence (§9.3); a series is expanded above
-- the store (SEARCH.md).
SELECT i.seq, i.link_id, i.flags, i.object_hash, i.sort_key, i.level,
       s.uid, s.summary, s.location, s.dtstart, s.dtstart_tzid, s.dtstart_value,
       s.dtend, s.recurring, s.until
FROM items i LEFT JOIN event_summary s ON s.collection = i.collection AND s.link_id = i.link_id
WHERE i.collection = :collection AND i.deleted = 0
  AND (i.sort_key, i.seq) > (:after_key, :after_seq)
ORDER BY i.sort_key, i.seq LIMIT :limit;
