-- The store-wide size of the bodies retention is holding, each object counted
-- once. An upper bound on what a purge reclaims: an object a live item also
-- points at keeps a reference and survives the collector (§5).
SELECT coalesce(sum(o.size), 0) FROM objects o WHERE o.hash IN
    (SELECT object_hash FROM items
     WHERE retained_at IS NOT NULL AND object_hash IS NOT NULL);
