-- Sender and subject search until SEARCH.md's index (§14.1): :pattern is a
-- LIKE pattern the caller builds, `%` around the words and `\` escaping a
-- literal `%`, `_` or `\`, matched against the subject, the sender's address
-- and its display name, ASCII case folded as LIKE does. Under the filters, on
-- list_mail_page_filtered's cursor and order, and merged as it is: each
-- collection seeks items_by_sort below the cursor and answers at most :limit
-- hits, so a page is capped at the set's size times :limit rows, while a
-- pattern a collection never matches reads that collection's summaries once.
-- Not the body: a hit list says so.
SELECT i.collection, i.seq, i.link_id,
       CASE WHEN i.flags_known = 1
            THEN trim(CASE WHEN i.marks & 1 THEN '\Seen ' ELSE '' END
                   || CASE WHEN i.marks & 2 THEN '\Answered ' ELSE '' END
                   || CASE WHEN i.marks & 4 THEN '\Flagged ' ELSE '' END
                   || CASE WHEN i.marks & 8 THEN '\Draft ' ELSE '' END
                   || CASE WHEN i.marks & 16 THEN '\Deleted ' ELSE '' END
                   || coalesce((SELECT group_concat(f.flag, ' ') FROM placement_flag f WHERE f.item = i.id), '')) END AS flags,
       i.object_hash, i.sort_key, i.level,
       s.message_id, s.subject, s.sender, s.sender_name, s.date, s.size, s.attachment
FROM (SELECT DISTINCT value AS id FROM temp.param WHERE slot = 'collections') p
JOIN items i ON i.rowid IN (
  SELECT x.rowid FROM items x
  WHERE x.collection = p.id AND x.deleted = 0
    AND (x.sort_key, x.seq) <= (coalesce(:after_key, x''), coalesce(:after_seq, 0))
    AND (x.sort_key, x.seq, x.collection)
        < (coalesce(:after_key, x''), coalesce(:after_seq, 0), coalesce(:after_collection, ''))
    AND EXISTS (SELECT 1 FROM mail_summary a
                WHERE a.item = x.id
                  AND (a.subject LIKE :pattern ESCAPE '\' OR a.sender LIKE :pattern ESCAPE '\'
                       OR a.sender_name LIKE :pattern ESCAPE '\')
                  AND (:attachment IS NULL OR a.attachment = :attachment))
    AND (:seen IS NULL
         OR :seen = (x.marks & 1))
  ORDER BY x.sort_key DESC, x.seq DESC LIMIT :limit)
JOIN mail_summary s ON s.item = i.id
ORDER BY i.sort_key DESC, i.seq DESC, i.collection DESC LIMIT :limit;
