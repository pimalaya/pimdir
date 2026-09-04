-- The dedup axis rather than the identity one (§9), so this finds the same
-- message delivered to two accounts even when the servers rewrote its link id.
SELECT i.collection, c.account, i.seq, i.link_id, i.flags, i.level
FROM items i JOIN collections c ON c.id = i.collection
WHERE i.object_hash = :hash AND i.deleted = 0 AND i.retained_at IS NULL
ORDER BY c.account IS NULL, c.account, i.collection;
