-- Records a reference (§14.2) between two items the store holds, each a kind
-- and a link id with at least one row in a collection of that kind, live or
-- not; an endpoint it holds no row of records nothing. A reference already
-- recorded is kept as it is, save that a person's (`user`) takes over a
-- rule's (`auto`), never the reverse. Returns the row when it recorded or
-- took one over, nothing otherwise.
INSERT INTO item_reference(from_kind, from_link_id, to_kind, to_link_id, role, origin, created_at)
SELECT :from_kind, :from_link_id, :to_kind, :to_link_id, :role, :origin,
       strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
WHERE EXISTS (SELECT 1 FROM items i JOIN collections c ON c.id = i.collection
              WHERE i.link_id = :from_link_id AND c.kind = :from_kind)
  AND EXISTS (SELECT 1 FROM items i JOIN collections c ON c.id = i.collection
              WHERE i.link_id = :to_link_id AND c.kind = :to_kind)
ON CONFLICT (from_link_id, from_kind, to_link_id, to_kind, role)
DO UPDATE SET origin = excluded.origin WHERE excluded.origin = 'user' AND origin = 'auto'
RETURNING from_kind, from_link_id, to_kind, to_link_id, role, origin, created_at;
