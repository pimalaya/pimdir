-- Sender and subject search until SEARCH.md's index (§14.1): :pattern is a
-- LIKE pattern the caller builds, `%` around the words and `\` escaping a
-- literal `%`, `_` or `\`, matched against the subject, the sender's address
-- and its display name, ASCII case folded as LIKE does. Under the chips and
-- on list_mail_page_filtered's cursor and order walk. Not the body: a hit
-- list says so.
SELECT i.collection, i.seq, i.link_id, i.flags, i.object_hash, i.sort_key, i.level,
       s.message_id, s.in_reply_to, s.subject, s.sender, s.sender_name, s.date, s.size, s.attachment
FROM items i JOIN mail_summary s ON s.collection = i.collection AND s.link_id = i.link_id
WHERE +i.collection IN (SELECT value FROM json_each(:collections)) AND i.deleted = 0
  AND (s.subject LIKE :pattern ESCAPE '\' OR s.sender LIKE :pattern ESCAPE '\'
       OR s.sender_name LIKE :pattern ESCAPE '\')
  AND (:seen IS NULL
       OR :seen = EXISTS (SELECT 1 FROM json_each(i.flags) WHERE value = '\Seen'))
  AND (:attachment IS NULL OR s.attachment = :attachment)
  AND (:after_key IS NULL
       OR (i.sort_key, i.seq, i.collection) < (:after_key, :after_seq, :after_collection))
ORDER BY i.sort_key DESC, i.seq DESC, i.collection DESC LIMIT :limit;
