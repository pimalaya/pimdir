-- Read from bindings rather than sources, so a source appears as soon as it
-- holds one item, without waiting for a checkpoint row. A loose scan of
-- bindings_by_handle: per collection, each step seeks the next source above
-- the last, so the read costs a seek per collection and source, never a
-- binding each.
WITH RECURSIVE bound(collection, source) AS (
    SELECT c.id, (SELECT min(b.source) FROM bindings b WHERE b.collection = c.id)
    FROM collections c
    UNION ALL
    SELECT bound.collection,
           (SELECT min(b.source) FROM bindings b
            WHERE b.collection = bound.collection AND b.source > bound.source)
    FROM bound WHERE bound.source IS NOT NULL
)
SELECT DISTINCT source FROM bound WHERE source IS NOT NULL ORDER BY source;
