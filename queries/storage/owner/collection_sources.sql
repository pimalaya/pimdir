-- The sources syncing one collection, by a binding or a checkpoint of their
-- own, so a run knows whether it syncs beside others (SYNC §5): a source
-- whose remote dropped its last member keeps its checkpoint. The binding
-- half is a loose scan of bindings_by_handle: each step seeks the next source
-- above the last, so a collection of any size is read in as many seeks as it
-- has sources, once per drained add, move or copy.
WITH RECURSIVE bound(source) AS (
    SELECT min(b.source) FROM bindings b WHERE b.collection = :collection
    UNION ALL
    SELECT (SELECT min(b.source) FROM bindings b
            WHERE b.collection = :collection AND b.source > bound.source)
    FROM bound WHERE bound.source IS NOT NULL
)
SELECT source FROM sources WHERE collection = :collection
UNION
SELECT source FROM bound WHERE source IS NOT NULL;
