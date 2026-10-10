-- The placements at the other end of an item's references (§8), either
-- direction: :kind and :link_id name the item as `id:` resolves it, :role
-- narrows to one role or NULL for any. Read from the store, which records
-- references; the index derives none.
SELECT i.collection, i.seq
FROM store.item_reference r
JOIN store.items i ON i.link_id = r.to_link_id AND i.deleted = 0
JOIN store.collections c ON c.id = i.collection AND c.kind = r.to_kind
WHERE r.from_kind = :kind AND r.from_link_id = :link_id AND (:role IS NULL OR r.role = :role)
UNION
SELECT i.collection, i.seq
FROM store.item_reference r
JOIN store.items i ON i.link_id = r.from_link_id AND i.deleted = 0
JOIN store.collections c ON c.id = i.collection AND c.kind = r.from_kind
WHERE r.to_kind = :kind AND r.to_link_id = :link_id AND (:role IS NULL OR r.role = :role);
