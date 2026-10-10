-- The references one item makes (§14.2), by kind and link id, in the order
-- of the other end and the role. Whether that end is live is the reader's
-- to ask (list_link_placements).
SELECT from_kind, from_link_id, to_kind, to_link_id, role, origin, created_at
FROM item_reference
WHERE from_kind = :kind AND from_link_id = :link_id
ORDER BY to_link_id, to_kind, role;
