-- Read from bindings rather than sources, so a source appears as soon as it
-- holds one item, without waiting for a checkpoint row.
SELECT DISTINCT source FROM bindings ORDER BY source;
