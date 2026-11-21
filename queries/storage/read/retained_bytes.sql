-- The store-wide size of the bodies retention is holding, each object counted
-- once, read from items_by_retained alone. An upper bound on what a purge
-- reclaims: an object a live item also points at keeps a reference and
-- survives the collector (§5).
SELECT coalesce(sum(o.size), 0) AS bytes FROM objects o WHERE o.id IN
    (SELECT object FROM items
     WHERE retained_at IS NOT NULL AND object IS NOT NULL);
