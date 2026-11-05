-- A newest-first page over a set of collections (the `collections` slot)
-- under count_mail's filters and :since, so a list sized by that count
-- loads around the scroll position and its walk ends at the floor. One seq
-- is shared by an identity's placements (§9.1), so the cursor is (sort_key,
-- seq, collection); a NULL :after_key is the first page. A merge (§9.3): each
-- collection of the set seeks items_by_sort below the cursor and answers at
-- most :limit rows under the filters, and their union is ordered and cut, so a
-- page reads at most the set's size times :limit rows and never another
-- kind's. The cursor is coalesced to the empty blob, above every text, so it
-- stays the seek's bound on the first page too.
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
    AND x.sort_key >= coalesce(:since, '')
    AND (x.sort_key, x.seq) <= (coalesce(:after_key, x''), coalesce(:after_seq, 0))
    AND (x.sort_key, x.seq, x.collection)
        < (coalesce(:after_key, x''), coalesce(:after_seq, 0), coalesce(:after_collection, ''))
    AND (:seen IS NULL
         OR :seen = (x.marks & 1))
    AND (:attachment IS NULL
         OR EXISTS (SELECT 1 FROM mail_summary a
                    WHERE a.item = x.id AND a.attachment = :attachment))
  ORDER BY x.sort_key DESC, x.seq DESC LIMIT :limit)
LEFT JOIN mail_summary s ON s.item = i.id
ORDER BY i.sort_key DESC, i.seq DESC, i.collection DESC LIMIT :limit;
