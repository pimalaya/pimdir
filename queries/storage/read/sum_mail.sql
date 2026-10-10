-- What count_mail counts, over the sort keys in [:since, :until), either
-- bound NULL for open: the messages, the bytes of those whose size is known,
-- and how many have none (NULL), so a reader says what a range of dates
-- weighs. A message is counted once however many collections of the set file
-- it (its `seq`, §9.1), its size the largest a placement states. :held 1
-- keeps the messages a placement holds the body of, 0 those none does, which
-- is what a download would fetch (a held body is linked, SYNC §6), NULL
-- either. An undated row ('') lies below any date, so only a range open below
-- holds it. An open :until reads as the empty blob, which SQLite orders above
-- every text, so both bounds stay seeks on items_by_sort.
SELECT count(*), coalesce(sum(size), 0), count(*) - count(size)
FROM (
  SELECT i.seq, max(s.size) AS size
  FROM items i
  LEFT JOIN mail_summary s ON s.collection = i.collection AND s.link_id = i.link_id
  WHERE i.collection IN (SELECT value FROM json_each(:collections)) AND i.deleted = 0
    AND (:seen IS NULL
         OR :seen = EXISTS (SELECT 1 FROM json_each(i.flags) WHERE value = '\Seen'))
    AND (:attachment IS NULL OR s.attachment = :attachment)
    AND i.sort_key >= coalesce(:since, '') AND i.sort_key < coalesce(:until, x'')
  GROUP BY i.seq
  HAVING :held IS NULL OR :held = max(i.object_hash IS NOT NULL)
);
