-- Sender and subject search until SEARCH.md's index (§14.1): :pattern is a
-- LIKE pattern the caller builds, `%` around the words and `\` escaping a
-- literal `%`, `_` or `\`, matched against the subject, the sender's address
-- and its display name, ASCII case folded as LIKE does. Under the chips and
-- on list_mail_page_filtered's cursor and order walk. Not the body: a hit
-- list says so.
SELECT i.collection, i.seq, i.link_id,
       CASE WHEN i.flags_known = 1
            THEN coalesce((SELECT group_concat(f.flag, ' ') FROM placement_flag f
                           WHERE f.collection = i.collection AND f.link_id = i.link_id), '') END AS flags,
       i.object_hash, i.sort_key, i.level,
       s.message_id, s.subject, s.sender, s.sender_name, s.date, s.size, s.attachment
FROM items i JOIN mail_summary s ON s.collection = i.collection AND s.link_id = i.link_id
WHERE +i.collection IN (SELECT value FROM temp.param WHERE slot = 'collections') AND i.deleted = 0
  AND (s.subject LIKE :pattern ESCAPE '\' OR s.sender LIKE :pattern ESCAPE '\'
       OR s.sender_name LIKE :pattern ESCAPE '\')
  AND (:seen IS NULL
       OR :seen = EXISTS (SELECT 1 FROM placement_flag f
                          WHERE f.collection = i.collection AND f.link_id = i.link_id AND f.flag = '\Seen'))
  AND (:attachment IS NULL OR s.attachment = :attachment)
  AND (:after_key IS NULL
       OR (i.sort_key, i.seq, i.collection) < (:after_key, :after_seq, :after_collection))
ORDER BY i.sort_key DESC, i.seq DESC, i.collection DESC LIMIT :limit;
