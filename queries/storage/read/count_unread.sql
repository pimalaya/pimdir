-- The unread mail of each collection of a set (the `collections` slot),
-- under the attachment filter and above the :since floor as count_mail reads
-- them. A collection with none has no row.
SELECT i.collection, count(*)
FROM items i
WHERE i.collection IN (SELECT value FROM temp.param WHERE slot = 'collections') AND i.deleted = 0
  AND NOT EXISTS (SELECT 1 FROM placement_flag f
                  WHERE f.collection = i.collection AND f.link_id = i.link_id AND f.flag = '\Seen')
  AND (:attachment IS NULL
       OR EXISTS (SELECT 1 FROM mail_summary s
                  WHERE s.collection = i.collection AND s.link_id = i.link_id AND s.attachment = :attachment))
  AND i.sort_key >= coalesce(:since, '')
GROUP BY i.collection ORDER BY i.collection;
