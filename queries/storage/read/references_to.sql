-- The references made to one item (§14.2), by kind and link id, in the order
-- of the other end and the role. Whether that end is live is the reader's
-- to ask (list_link_placements).
SELECT from_kind, from_link_id, to_kind, to_link_id, role, origin, created_at
FROM item_reference
WHERE to_kind = :kind AND to_link_id = :link_id
ORDER BY from_link_id, from_kind, role;
