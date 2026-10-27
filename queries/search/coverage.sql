-- What a result set could not see (§8): live items with no body, per kind,
-- of the kinds whose body search reads. A file is indexed from its summary
-- alone (§6), so a bodiless one hides nothing and is never counted.
SELECT c.kind, count(*) FROM store.items i JOIN store.collections c ON c.id = i.collection
WHERE i.object_hash IS NULL AND i.deleted = 0 AND i.retained_at IS NULL
  AND c.kind <> 'application/octet-stream'
GROUP BY c.kind;
