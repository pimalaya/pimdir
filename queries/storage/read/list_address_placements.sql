-- Every live placement naming one address, store-wide, once per role it names
-- it in (its first position there); :role NULL for any role. Newest first, a
-- keyset page on (sort_key, seq, collection, role), a NULL :after_key the
-- first page, coalesced to the empty blob above every text. A seek on
-- item_address_by_address however large the store: a page reads the
-- address's placements, which the index names without reading a row, and
-- keeps the :limit newest, holding no more than those.
SELECT a.role, i.collection, c.account, c.kind, i.seq, i.sort_key
FROM item_address a
JOIN items i ON i.collection = a.collection AND i.link_id = a.link_id
JOIN collections c ON c.id = i.collection
WHERE a.address = :address AND (:role IS NULL OR a.role = :role)
  AND NOT EXISTS (SELECT 1 FROM item_address d
                  WHERE d.address = a.address AND d.role = a.role AND d.collection = a.collection
                    AND d.link_id = a.link_id AND d.position < a.position)
  AND i.deleted = 0 AND i.retained_at IS NULL
  AND (i.sort_key, i.seq, i.collection, a.role)
      < (coalesce(:after_key, x''), coalesce(:after_seq, 0), coalesce(:after_collection, ''),
         coalesce(:after_role, ''))
ORDER BY i.sort_key DESC, i.seq DESC, i.collection DESC, a.role DESC LIMIT :limit;
