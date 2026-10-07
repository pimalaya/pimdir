-- count_mail per day of the sort key, the `Date` (Annex A.1), newest day
-- first and the undated (NULL) last. :shift is a SQLite date modifier moving
-- the UTC instant to the reader's wall clock ('+120 minutes'); NULL reads
-- UTC days.
SELECT date(nullif(i.sort_key, ''), coalesce(:shift, '+0 minutes')) AS day, count(*)
FROM items i
LEFT JOIN mail_summary s ON s.collection = i.collection AND s.link_id = i.link_id
WHERE i.collection IN (SELECT value FROM json_each(:collections)) AND i.deleted = 0
  AND (:seen IS NULL
       OR :seen = EXISTS (SELECT 1 FROM json_each(i.flags) WHERE value = '\Seen'))
  AND (:attachment IS NULL OR s.attachment = :attachment)
GROUP BY day ORDER BY day DESC;
