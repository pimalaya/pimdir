-- What every source binding one item can do in its collection (§15.6): what
-- an action on it needs, each of them pushing it. A row naming the collection
-- wins over the source-wide row; an undeclared source comes back once with a
-- NULL capability, as in load_capabilities.
WITH holders AS (
    SELECT b.source FROM bindings b JOIN items i ON i.collection = b.collection AND i.link_id = b.link_id
    WHERE i.collection = :collection AND i.seq = :seq
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
SELECT h.source, e.capability, e.support, e.detail
FROM holders h LEFT JOIN effective e ON e.source = h.source
ORDER BY h.source, e.capability;
