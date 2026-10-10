-- Events, tasks and journals of a set of collections whose summary (or an
-- event's location) matches :pattern, on search_contacts's terms, ordered on
-- the sort key (§9.3), each row naming its component and its summary.
SELECT collection, seq, link_id, flags, object_hash, sort_key, level, component, title
FROM (
  SELECT i.collection, i.seq, i.link_id, i.flags, i.object_hash, i.sort_key, i.level,
         'event' AS component, s.summary AS title
  FROM items i JOIN event_summary s ON s.collection = i.collection AND s.link_id = i.link_id
  WHERE (s.summary LIKE :pattern ESCAPE '\' OR s.location LIKE :pattern ESCAPE '\')
    AND i.collection IN (SELECT value FROM json_each(:collections)) AND i.deleted = 0
  UNION ALL
  SELECT i.collection, i.seq, i.link_id, i.flags, i.object_hash, i.sort_key, i.level,
         'task', s.summary
  FROM items i JOIN task_summary s ON s.collection = i.collection AND s.link_id = i.link_id
  WHERE s.summary LIKE :pattern ESCAPE '\'
    AND i.collection IN (SELECT value FROM json_each(:collections)) AND i.deleted = 0
  UNION ALL
  SELECT i.collection, i.seq, i.link_id, i.flags, i.object_hash, i.sort_key, i.level,
         'journal', s.summary
  FROM items i JOIN journal_summary s ON s.collection = i.collection AND s.link_id = i.link_id
  WHERE s.summary LIKE :pattern ESCAPE '\'
    AND i.collection IN (SELECT value FROM json_each(:collections)) AND i.deleted = 0
)
WHERE :after_key IS NULL OR (sort_key, seq, collection) > (:after_key, :after_seq, :after_collection)
ORDER BY sort_key, seq, collection LIMIT :limit;
