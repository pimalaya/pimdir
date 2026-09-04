-- Every live placement naming one address, store-wide; :role NULL for any
-- role. A seek on item_address_by_address however large the store.
SELECT a.role, i.collection, c.account, c.kind, i.seq, i.sort_key
FROM item_address a
JOIN items i ON i.collection = a.collection AND i.link_id = a.link_id
JOIN collections c ON c.id = i.collection
WHERE a.address = :address AND (:role IS NULL OR a.role = :role)
  AND i.deleted = 0 AND i.retained_at IS NULL
ORDER BY i.sort_key DESC, i.seq DESC;
