-- The values one key holds across the store, each once, in byte order: the
-- labels a picker offers, and the spellings label: folds to find those a
-- query names (SEARCH.md §8). Each value is one seek on item_property_by_value
-- past the one before, so the read costs the values the key holds, never the
-- rows holding them.
WITH RECURSIVE held(value) AS (
    SELECT min(value) FROM item_property WHERE key = :key
    UNION ALL
    SELECT (SELECT min(p.value) FROM item_property p WHERE p.key = :key AND p.value > held.value)
    FROM held WHERE held.value IS NOT NULL
)
SELECT value FROM held WHERE value IS NOT NULL;
