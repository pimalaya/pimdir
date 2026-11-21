-- `coverage` over every collection of the store (§8.2), what a query no
-- conjunct narrows reads: the same four counts per kind, the slot left
-- unbound. The bodiless live items are walked once on the store's
-- items_bodiless, which holds them alone, rather than sought per collection,
-- and missing and the bodies not read whole likewise (object_not_ok to their
-- placements, the CROSS JOIN), so its cost is the rows counted, never the
-- collections. It answers what `coverage` answers bound to every collection.
SELECT kind, sum(bodiless) AS bodiless, sum(missing) AS missing,
       sum(unparseable) AS unparseable, sum(encrypted) AS encrypted
FROM (
    SELECT c.kind AS kind, count(*) AS bodiless, 0 AS missing, 0 AS unparseable, 0 AS encrypted
    FROM store.items i INDEXED BY items_bodiless
    JOIN store.collections c ON c.id = i.collection
    WHERE i.object IS NULL AND i.deleted = 0
      AND c.kind <> 'application/octet-stream'
    GROUP BY c.kind
    UNION ALL
    SELECT c.kind, 0, count(*), 0, 0
    FROM missing m JOIN store.collections c ON c.id = m.collection
    GROUP BY c.kind
    UNION ALL
    SELECT c.kind, 0, 0, sum(o.status <> 'encrypted'), sum(o.status = 'encrypted')
    FROM object o
    CROSS JOIN placement p ON p.object = o.id
    JOIN store.collections c ON c.id = p.collection
    WHERE o.status <> 'ok'
    GROUP BY c.kind
)
GROUP BY kind;
