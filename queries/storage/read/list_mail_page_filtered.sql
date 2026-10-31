-- A newest-first page over a set of collections (the `collections` slot)
-- under count_mail's chips and :since, so a list sized by that count
-- loads around the scroll position and its walk ends at the floor. One seq
-- is shared by an identity's placements (§9.1), so the cursor is (sort_key,
-- seq, collection); a NULL :after_key is the first page. It walks
-- items_by_sort_global; the `+` keeps the collection test off items_by_seq,
-- which a planner without statistics would pick and then sort every row of
-- the set.
SELECT i.collection, i.seq, i.link_id,
       CASE WHEN i.flags_known = 1
            THEN coalesce((SELECT group_concat(f.flag, ' ') FROM placement_flag f
                           WHERE f.collection = i.collection AND f.link_id = i.link_id), '') END AS flags,
       i.object_hash, i.sort_key, i.level,
       s.message_id, s.subject, s.sender, s.sender_name, s.date, s.size, s.attachment
FROM items i LEFT JOIN mail_summary s ON s.collection = i.collection AND s.link_id = i.link_id
WHERE +i.collection IN (SELECT value FROM temp.param WHERE slot = 'collections') AND i.deleted = 0
  AND (:seen IS NULL
       OR :seen = EXISTS (SELECT 1 FROM placement_flag f
                          WHERE f.collection = i.collection AND f.link_id = i.link_id AND f.flag = '\Seen'))
  AND (:attachment IS NULL OR s.attachment = :attachment)
  AND i.sort_key >= coalesce(:since, '')
  AND (:after_key IS NULL
       OR (i.sort_key, i.seq, i.collection) < (:after_key, :after_seq, :after_collection))
ORDER BY i.sort_key DESC, i.seq DESC, i.collection DESC LIMIT :limit;
