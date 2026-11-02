-- Events, tasks and journals of a set of collections whose summary (or an
-- event's location) matches :pattern, on search_contacts's terms, ordered on
-- the sort key (§9.3), each row naming its component and its summary. An item
-- has one component's summary at most (§14), so a row reads the one it has.
SELECT i.collection, i.seq, i.link_id,
       CASE WHEN i.flags_known = 1
            THEN coalesce((SELECT group_concat(f.flag, ' ') FROM placement_flag f
                           WHERE f.collection = i.collection AND f.link_id = i.link_id), '') END AS flags,
       i.object_hash, i.sort_key, i.level,
       CASE WHEN e.link_id IS NOT NULL THEN 'event' WHEN t.link_id IS NOT NULL THEN 'task'
            ELSE 'journal' END AS component,
       coalesce(e.summary, t.summary, j.summary) AS title
FROM (SELECT DISTINCT value AS id FROM temp.param WHERE slot = 'collections') p
JOIN items i ON i.rowid IN (
  SELECT x.rowid FROM items x
  WHERE x.collection = p.id AND x.deleted = 0
    AND (x.sort_key, x.seq) >= (coalesce(:after_key, ''), coalesce(:after_seq, 0))
    AND (x.sort_key, x.seq, x.collection)
        > (coalesce(:after_key, ''), coalesce(:after_seq, 0), coalesce(:after_collection, ''))
    AND (EXISTS (SELECT 1 FROM event_summary m
                 WHERE m.collection = x.collection AND m.link_id = x.link_id
                   AND (m.summary LIKE :pattern ESCAPE '\' OR m.location LIKE :pattern ESCAPE '\'))
         OR EXISTS (SELECT 1 FROM task_summary m
                    WHERE m.collection = x.collection AND m.link_id = x.link_id
                      AND m.summary LIKE :pattern ESCAPE '\')
         OR EXISTS (SELECT 1 FROM journal_summary m
                    WHERE m.collection = x.collection AND m.link_id = x.link_id
                      AND m.summary LIKE :pattern ESCAPE '\'))
  ORDER BY x.sort_key, x.seq LIMIT :limit)
LEFT JOIN event_summary e ON e.collection = i.collection AND e.link_id = i.link_id
LEFT JOIN task_summary t ON t.collection = i.collection AND t.link_id = i.link_id
LEFT JOIN journal_summary j ON j.collection = i.collection AND j.link_id = i.link_id
ORDER BY i.sort_key, i.seq, i.collection LIMIT :limit;
