-- The unread mail of each collection of a set (:collections, a JSON array),
-- under the attachment chip as count_mail reads it. A collection with none
-- has no row.
SELECT i.collection, count(*)
FROM items i
LEFT JOIN mail_summary s ON s.collection = i.collection AND s.link_id = i.link_id
WHERE i.collection IN (SELECT value FROM json_each(:collections)) AND i.deleted = 0
  AND NOT EXISTS (SELECT 1 FROM json_each(i.flags) WHERE value = '\Seen')
  AND (:attachment IS NULL OR s.attachment = :attachment)
GROUP BY i.collection ORDER BY i.collection;
