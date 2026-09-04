-- The same for one domain. A suffix match is a scan, which is why the search
-- index tokenises the domain on its own (SEARCH.md).
SELECT a.address, a.role, i.collection, c.account, c.kind, i.seq, i.sort_key
FROM item_address a
JOIN items i ON i.collection = a.collection AND i.link_id = a.link_id
JOIN collections c ON c.id = i.collection
WHERE a.address LIKE '%@' || :domain AND (:role IS NULL OR a.role = :role)
  AND i.deleted = 0 AND i.retained_at IS NULL
ORDER BY i.sort_key DESC, i.seq DESC;
