-- What every source syncing a collection, by a binding or a checkpoint, can
-- do there (§15.6): what an `add` there needs. A row naming the collection
-- wins over the source-wide row for the same capability. An undeclared
-- source comes back once with a NULL capability, so a producer tells
-- "declares nothing" from "does not support this".
WITH syncing AS (
    SELECT source FROM sources WHERE collection = :collection
    UNION
    SELECT source FROM bindings WHERE collection = :collection
),
effective AS (
    SELECT source, capability, support, detail FROM capabilities WHERE collection = :collection
    UNION ALL
    SELECT w.source, w.capability, w.support, w.detail FROM capabilities w
    WHERE w.collection IS NULL AND NOT EXISTS (
        SELECT 1 FROM capabilities o
        WHERE o.source = w.source AND o.collection = :collection AND o.capability = w.capability
    )
)
SELECT s.source, e.capability, e.support, e.detail
FROM syncing s LEFT JOIN effective e ON e.source = s.source
ORDER BY s.source, e.capability;
