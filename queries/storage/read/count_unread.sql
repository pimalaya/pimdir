-- The unread mail of each collection of a set (the `collections` slot),
-- under the attachment filter and above the :since floor as count_mail reads
-- them. A collection with none has no row. The unread test is spelled as
-- items_unread states it, the partial index the count is told to read: it
-- holds the unread rows alone, so a mailbox mostly read counts few.
SELECT i.collection, count(*) AS count
FROM items i INDEXED BY items_unread
WHERE i.collection IN (SELECT value FROM temp.param WHERE slot = 'collections') AND i.deleted = 0
  AND i.marks & 1 = 0
  AND (:attachment IS NULL
       OR EXISTS (SELECT 1 FROM mail_summary s
                  WHERE s.item = i.id AND s.attachment = :attachment))
  AND i.sort_key >= coalesce(:since, '')
GROUP BY i.collection ORDER BY i.collection;
