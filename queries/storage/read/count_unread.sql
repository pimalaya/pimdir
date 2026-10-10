-- The unread mail of each collection of a set (:collections, a JSON array),
-- under the attachment chip and above the :since floor as count_mail reads
-- them. A collection with none has no row.
SELECT i.collection, count(*)
FROM items i
LEFT JOIN mail_summary s ON s.collection = i.collection AND s.link_id = i.link_id
WHERE i.collection IN (SELECT value FROM json_each(:collections)) AND i.deleted = 0
  AND NOT EXISTS (SELECT 1 FROM json_each(i.flags) WHERE value = '\Seen')
  AND (:attachment IS NULL OR s.attachment = :attachment)
  AND i.sort_key >= coalesce(:since, '')
GROUP BY i.collection ORDER BY i.collection;
