-- count_mail per day of the sort key, the `Date` (Annex A.1), newest day
-- first and the undated (NULL) last, above the same :since. :shift is the
-- reader's offset from UTC in whole minutes (120 east, -300 west), added to
-- the instant before its day is read; NULL reads UTC days.
SELECT date(nullif(i.sort_key, ''), coalesce(:shift, 0) || ' minutes') AS day, count(*)
FROM items i
WHERE i.collection IN (SELECT value FROM temp.param WHERE slot = 'collections') AND i.deleted = 0
  AND (:seen IS NULL
       OR :seen = (i.marks & 1))
  AND (:attachment IS NULL
       OR EXISTS (SELECT 1 FROM mail_summary s
                  WHERE s.item = i.id AND s.attachment = :attachment))
  AND i.sort_key >= coalesce(:since, '')
GROUP BY day ORDER BY day DESC;
