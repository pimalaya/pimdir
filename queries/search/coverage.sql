-- What a result set could not see (§8): live items with no body, per kind.
SELECT c.kind, count(*) FROM store.items i JOIN store.collections c ON c.id = i.collection
WHERE i.object_hash IS NULL AND i.deleted = 0 AND i.retained_at IS NULL
GROUP BY c.kind;
