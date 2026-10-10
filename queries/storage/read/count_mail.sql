-- The live mail of a set of collections (:collections, a JSON array) under
-- the chips (§14.1): :seen 1 read, 0 unread, NULL either; :attachment 1
-- with, 0 without, NULL either. A flag set holding no `\Seen`, unknown
-- included, is unread; an attachment mark never examined (NULL, an earlier
-- draft's Meta row) matches neither chip. :since is a floor on the sort key,
-- the `Date` (Annex A.1): a row below it is left out, an undated one ('')
-- below any; NULL is no floor.
SELECT count(*)
FROM items i
LEFT JOIN mail_summary s ON s.collection = i.collection AND s.link_id = i.link_id
WHERE i.collection IN (SELECT value FROM json_each(:collections)) AND i.deleted = 0
  AND (:seen IS NULL
       OR :seen = EXISTS (SELECT 1 FROM json_each(i.flags) WHERE value = '\Seen'))
  AND (:attachment IS NULL OR s.attachment = :attachment)
  AND i.sort_key >= coalesce(:since, '');
