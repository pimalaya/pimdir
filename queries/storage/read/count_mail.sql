-- The live mail of a set of collections (the `collections` slot) under
-- the filters (§14.1): :seen 1 read, 0 unread, NULL either; :attachment 1
-- with, 0 without, NULL either. A flag set holding no `\Seen`, unknown
-- included, is unread; an attachment mark never examined (NULL) matches
-- neither filter. :since is a floor on the sort key, the `Date` (Annex A.1): a
-- row below it is left out, an undated one ('') below any; NULL is no floor.
-- The seen test is a seek on placement_flag's key and the summary is read
-- only for the attachment filter, so with both NULL a count reads
-- items_by_sort alone.
SELECT count(*)
FROM items i
WHERE i.collection IN (SELECT value FROM temp.param WHERE slot = 'collections') AND i.deleted = 0
  AND (:seen IS NULL
       OR :seen = EXISTS (SELECT 1 FROM placement_flag f
                          WHERE f.collection = i.collection AND f.link_id = i.link_id AND f.flag = '\Seen'))
  AND (:attachment IS NULL
       OR EXISTS (SELECT 1 FROM mail_summary s
                  WHERE s.collection = i.collection AND s.link_id = i.link_id AND s.attachment = :attachment))
  AND i.sort_key >= coalesce(:since, '');
