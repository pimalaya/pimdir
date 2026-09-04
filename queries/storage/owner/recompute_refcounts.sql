-- Recount from the five pointers that pin an object, in one grouped pass, so
-- O(items+bindings+queue). The correlated-subquery form is O(objects x items),
-- since the OR across object_hash and conflict_object is a disjunction no index
-- serves: on twenty thousand items it took 80 seconds against this one's 121 ms.
-- The left join is what settles an object no pointer names any more, counting
-- zero rather than leaving it unvisited (§5).
UPDATE objects SET refcount = counted.n
FROM (
  SELECT o.hash AS hash, count(r.hash) AS n FROM objects o
  LEFT JOIN (
    SELECT object_hash AS hash FROM items WHERE object_hash IS NOT NULL
    UNION ALL SELECT conflict_object FROM items WHERE conflict_object IS NOT NULL
    UNION ALL SELECT base_object FROM bindings WHERE base_object IS NOT NULL
    UNION ALL SELECT conflict_object FROM bindings WHERE conflict_object IS NOT NULL
    UNION ALL SELECT object_hash FROM queue WHERE object_hash IS NOT NULL
  ) r ON r.hash = o.hash
  GROUP BY o.hash
) AS counted
WHERE counted.hash = objects.hash AND objects.refcount != counted.n;
