-- What count_mail counts, over the sort keys in [:since, :until), either
-- bound NULL for open: the rows, the bytes of those whose size is known, and
-- how many have none (NULL), so a reader says what a range of dates weighs
-- before downloading it. An undated row ('') lies below any date, so only a
-- range open below holds it. An open :until reads as the empty blob, which
-- SQLite orders above every text, so both bounds stay seeks on items_by_sort.
SELECT count(*), coalesce(sum(s.size), 0), count(*) - count(s.size)
FROM items i
LEFT JOIN mail_summary s ON s.collection = i.collection AND s.link_id = i.link_id
WHERE i.collection IN (SELECT value FROM json_each(:collections)) AND i.deleted = 0
  AND (:seen IS NULL
       OR :seen = EXISTS (SELECT 1 FROM json_each(i.flags) WHERE value = '\Seen'))
  AND (:attachment IS NULL OR s.attachment = :attachment)
  AND i.sort_key >= coalesce(:since, '') AND i.sort_key < coalesce(:until, x'');
