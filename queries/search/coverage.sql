-- What a result set could not see (§8.2): live items with no body, per kind,
-- among the query's collections (the `collections` slot), of the kinds whose
-- body search reads. A file is indexed from its summary alone (§6), so a
-- bodiless one hides nothing and is never counted. Each collection seeks the
-- store's items_bodiless, never the store's other rows.
SELECT c.kind, count(*) FROM store.collections c
JOIN store.items i ON i.collection = c.id AND i.object_hash IS NULL AND i.deleted = 0
WHERE c.id IN (SELECT value FROM temp.param WHERE slot = 'collections')
  AND c.kind <> 'application/octet-stream'
GROUP BY c.kind;
