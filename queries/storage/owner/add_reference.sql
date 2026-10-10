-- Records a reference (§14.2) between two items the store holds, each a kind
-- and a link id with at least one row in a collection of that kind, live or
-- not; an endpoint it holds no row of records nothing. A reference already
-- recorded is kept as it is, save that a person's (`user`) takes over a
-- rule's (`auto`), never the reverse. An end under a writer-derived key,
-- naming no identity (§9), records nothing either. Returns the reference as
-- it stands, recorded now or before, so a caller tells "linked" from an end
-- missing or derived, which returns no row.
INSERT INTO item_reference(from_kind, from_link_id, to_kind, to_link_id, role, origin, created_at)
SELECT :from_kind, :from_link_id, :to_kind, :to_link_id, :role, :origin,
       strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
WHERE EXISTS (SELECT 1 FROM items i JOIN collections c ON c.id = i.collection
              WHERE i.link_id = :from_link_id AND c.kind = :from_kind)
  AND EXISTS (SELECT 1 FROM items i JOIN collections c ON c.id = i.collection
              WHERE i.link_id = :to_link_id AND c.kind = :to_kind)
  AND NOT (:from_link_id GLOB 'alt:*' OR :from_link_id GLOB 'dup:*' OR :from_link_id GLOB 'hash:*'
           OR :from_link_id GLOB 'part:alt:*' OR :from_link_id GLOB 'part:dup:*')
  AND NOT (:to_link_id GLOB 'alt:*' OR :to_link_id GLOB 'dup:*' OR :to_link_id GLOB 'hash:*'
           OR :to_link_id GLOB 'part:alt:*' OR :to_link_id GLOB 'part:dup:*')
ON CONFLICT (from_link_id, from_kind, to_link_id, to_kind, role)
DO UPDATE SET origin = iif(excluded.origin = 'user', 'user', origin)
RETURNING from_kind, from_link_id, to_kind, to_link_id, role, origin, created_at;
