-- A newest-first page over a set of collections (:collections, a JSON
-- array) under count_mail's chips, so a list sized by that count loads
-- around the scroll position. One seq is shared by an identity's placements
-- (§9.1), so the cursor is (sort_key, seq, collection); a NULL :after_key is
-- the first page.
SELECT i.collection, i.seq, i.link_id, i.flags, i.object_hash, i.sort_key, i.level,
       s.message_id, s.in_reply_to, s.subject, s.sender, s.sender_name, s.date, s.size, s.attachment
FROM items i LEFT JOIN mail_summary s ON s.collection = i.collection AND s.link_id = i.link_id
WHERE i.collection IN (SELECT value FROM json_each(:collections)) AND i.deleted = 0
  AND (:seen IS NULL
       OR :seen = EXISTS (SELECT 1 FROM json_each(i.flags) WHERE value = '\Seen'))
  AND (:attachment IS NULL OR s.attachment = :attachment)
  AND (:after_key IS NULL
       OR (i.sort_key, i.seq, i.collection) < (:after_key, :after_seq, :after_collection))
ORDER BY i.sort_key DESC, i.seq DESC, i.collection DESC LIMIT :limit;
