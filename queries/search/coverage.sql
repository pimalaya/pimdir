-- What a result set could not see (§8.2), per kind, among the query's
-- collections (the `collections` slot), of the kinds whose body search reads:
-- the live items with no body, read from the store, then, read from the
-- index, the placements whose body could not be read (missing) and those
-- whose body the extraction recorded unparseable or encrypted. A kind
-- counting none answers no row. A file is indexed from its summary alone
-- (§6), so a bodiless one hides nothing and is never counted. Each
-- collection seeks the store's items_bodiless, never the store's other rows,
-- and missing's key; the bodies not read whole are walked on object_not_ok
-- to their placements (the CROSS JOIN), never every placement of a
-- collection.
SELECT kind, sum(bodiless) AS bodiless, sum(missing) AS missing,
       sum(unparseable) AS unparseable, sum(encrypted) AS encrypted
FROM (
    SELECT c.kind AS kind, count(*) AS bodiless, 0 AS missing, 0 AS unparseable, 0 AS encrypted
    FROM store.collections c
    JOIN store.items i ON i.collection = c.id AND i.object_hash IS NULL AND i.deleted = 0
    WHERE c.id IN (SELECT value FROM temp.param WHERE slot = 'collections')
      AND c.kind <> 'application/octet-stream'
    GROUP BY c.kind
    UNION ALL
    SELECT c.kind, 0, count(*), 0, 0
    FROM missing m JOIN store.collections c ON c.id = m.collection
    WHERE m.collection IN (SELECT value FROM temp.param WHERE slot = 'collections')
    GROUP BY c.kind
    UNION ALL
    SELECT c.kind, 0, 0, sum(o.status = 'unparseable'), sum(o.status = 'encrypted')
    FROM object o
    CROSS JOIN placement p ON p.hash = o.hash
    JOIN store.collections c ON c.id = p.collection
    WHERE o.status <> 'ok'
      AND p.collection IN (SELECT value FROM temp.param WHERE slot = 'collections')
    GROUP BY c.kind
)
GROUP BY kind;
