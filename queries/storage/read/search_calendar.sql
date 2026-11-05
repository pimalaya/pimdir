-- Events, tasks and journals of a set of collections whose summary (or an
-- event's location) matches :pattern, on search_contacts's terms, ordered on
-- the sort key (§9.3), each row naming its component and its summary. An item
-- has one component's summary at most (§14), so a row reads the one it has.
SELECT i.collection, i.seq, i.link_id,
       CASE WHEN i.flags_known = 1
            THEN trim(CASE WHEN i.marks & 1 THEN '\Seen ' ELSE '' END
                   || CASE WHEN i.marks & 2 THEN '\Answered ' ELSE '' END
                   || CASE WHEN i.marks & 4 THEN '\Flagged ' ELSE '' END
                   || CASE WHEN i.marks & 8 THEN '\Draft ' ELSE '' END
                   || CASE WHEN i.marks & 16 THEN '\Deleted ' ELSE '' END
                   || coalesce((SELECT group_concat(f.flag, ' ') FROM placement_flag f WHERE f.item = i.id), '')) END AS flags,
       i.object_hash, i.sort_key, i.level,
       CASE WHEN e.item IS NOT NULL THEN 'event' WHEN t.item IS NOT NULL THEN 'task'
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
                 WHERE m.item = x.id
                   AND (m.summary LIKE :pattern ESCAPE '\' OR m.location LIKE :pattern ESCAPE '\'))
         OR EXISTS (SELECT 1 FROM task_summary m
                    WHERE m.item = x.id
                      AND m.summary LIKE :pattern ESCAPE '\')
         OR EXISTS (SELECT 1 FROM journal_summary m
                    WHERE m.item = x.id
                      AND m.summary LIKE :pattern ESCAPE '\'))
  ORDER BY x.sort_key, x.seq LIMIT :limit)
LEFT JOIN event_summary e ON e.item = i.id
LEFT JOIN task_summary t ON t.item = i.id
LEFT JOIN journal_summary j ON j.item = i.id
ORDER BY i.sort_key, i.seq, i.collection LIMIT :limit;
