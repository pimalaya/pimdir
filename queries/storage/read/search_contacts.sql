-- Contacts of a set of collections (:collections, a JSON array) whose name or
-- an `email` matches :pattern, a LIKE pattern built as for search_mail, A to
-- Z on the name across the set, cursor (sort_key, seq, collection), a NULL
-- :after_key the first page. Until SEARCH.md's index answers it.
SELECT i.collection, i.seq, i.link_id, i.flags, i.object_hash, i.sort_key, i.level,
       s.uid, s.fn, s.kind, s.org
FROM items i JOIN contact_summary s ON s.collection = i.collection AND s.link_id = i.link_id
WHERE i.collection IN (SELECT value FROM json_each(:collections)) AND i.deleted = 0
  AND (s.fn LIKE :pattern ESCAPE '\'
       OR EXISTS (SELECT 1 FROM item_address a
                  WHERE a.collection = i.collection AND a.link_id = i.link_id
                    AND a.role = 'email' AND a.address LIKE :pattern ESCAPE '\'))
  AND (:after_key IS NULL
       OR (i.sort_key, i.seq, i.collection) > (:after_key, :after_seq, :after_collection))
ORDER BY i.sort_key, i.seq, i.collection LIMIT :limit;
