-- Contacts of a set of collections (the `collections` slot) whose name or
-- an `email` matches :pattern, a LIKE pattern built as for search_mail, A to
-- Z on the name across the set, cursor (sort_key, seq, collection), a NULL
-- :after_key the first page. Until SEARCH.md's index answers it. Merged as
-- list_mail_page_filtered is, ascending: each collection seeks items_by_sort
-- above the cursor, coalesced to the empty text and seq 0, below every key,
-- and answers at most :limit hits.
SELECT i.collection, i.seq, i.link_id,
       CASE WHEN i.flags_known = 1
            THEN coalesce((SELECT group_concat(f.flag, ' ') FROM placement_flag f
                           WHERE f.collection = i.collection AND f.link_id = i.link_id), '') END AS flags,
       i.object_hash, i.sort_key, i.level,
       s.uid, s.fn, s.kind, s.org
FROM (SELECT DISTINCT value AS id FROM temp.param WHERE slot = 'collections') p
JOIN items i ON i.rowid IN (
  SELECT x.rowid FROM items x
  WHERE x.collection = p.id AND x.deleted = 0
    AND (x.sort_key, x.seq) >= (coalesce(:after_key, ''), coalesce(:after_seq, 0))
    AND (x.sort_key, x.seq, x.collection)
        > (coalesce(:after_key, ''), coalesce(:after_seq, 0), coalesce(:after_collection, ''))
    AND EXISTS (SELECT 1 FROM contact_summary c
                WHERE c.collection = x.collection AND c.link_id = x.link_id
                  AND (c.fn LIKE :pattern ESCAPE '\'
                       OR EXISTS (SELECT 1 FROM item_address a
                                  WHERE a.collection = x.collection AND a.link_id = x.link_id
                                    AND a.role = 'email' AND a.address LIKE :pattern ESCAPE '\')))
  ORDER BY x.sort_key, x.seq LIMIT :limit)
JOIN contact_summary s ON s.collection = i.collection AND s.link_id = i.link_id
ORDER BY i.sort_key, i.seq, i.collection LIMIT :limit;
