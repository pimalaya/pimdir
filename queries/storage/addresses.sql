-- pimdir addresses: the people an item names, by role, whatever its kind
-- (STORAGE.md §4.4, Annex A.6).
--
-- Reference statements for the store operations (STORAGE.md §4.4, §14); column
-- encodings in §13, named parameters `:name`.

-- name: replace_addresses
-- Replaced as a set: the derivation yields the whole list, and a diff buys
-- nothing on a handful of rows. Followed by stamp_item when nothing else
-- about the item moved (§4.5).
DELETE FROM item_address WHERE collection = :collection AND link_id = :link_id;

-- name: insert_address
INSERT INTO item_address(collection, link_id, role, position, address, name)
VALUES(:collection, :link_id, :role, :position, :address, :name);

-- name: load_addresses
-- One item's people, in document order within each role.
SELECT role, position, address, name FROM item_address
WHERE collection = :collection AND link_id = :link_id
ORDER BY role, position;

-- The client read surface (§14.1).

-- name: list_address_placements
-- Every live placement naming one address, store-wide; :role NULL for any
-- role. A seek on item_address_by_address however large the store.
SELECT a.role, i.collection, c.account, c.kind, i.seq, i.sort_key
FROM item_address a
JOIN items i ON i.collection = a.collection AND i.link_id = a.link_id
JOIN collections c ON c.id = i.collection
WHERE a.address = :address AND (:role IS NULL OR a.role = :role)
  AND i.deleted = 0 AND i.retained_at IS NULL
ORDER BY i.sort_key DESC, i.seq DESC;

-- name: list_domain_placements
-- The same for one domain. A suffix match is a scan, which is why the search
-- index tokenises the domain on its own (SEARCH.md).
SELECT a.address, a.role, i.collection, c.account, c.kind, i.seq, i.sort_key
FROM item_address a
JOIN items i ON i.collection = a.collection AND i.link_id = a.link_id
JOIN collections c ON c.id = i.collection
WHERE a.address LIKE '%@' || :domain AND (:role IS NULL OR a.role = :role)
  AND i.deleted = 0 AND i.retained_at IS NULL
ORDER BY i.sort_key DESC, i.seq DESC;
