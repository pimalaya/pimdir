-- Pairs by the assigned key, not by the identity hint it came from, so a
-- minted copy (§9) is not listed beside the item holding the bare hint;
-- list_object_placements pairs those two whenever their bodies agree.
SELECT i.collection, c.account, i.seq, i.object_hash, i.flags, i.level
FROM items i JOIN collections c ON c.id = i.collection
WHERE i.link_id = :link_id AND i.deleted = 0 AND i.retained_at IS NULL
ORDER BY c.account IS NULL, c.account, i.collection;
