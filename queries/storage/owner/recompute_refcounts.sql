-- Recount from the six pointers that pin an object in one grouped pass, linear
-- in the pointers (§7): a correlated subquery per object would be quadratic,
-- the OR across object_hash and conflict_object being a disjunction no index
-- serves. The left join is what settles an object no pointer names any more,
-- counting zero rather than leaving it unvisited (§5).
UPDATE objects SET refcount = counted.n
FROM (
  SELECT o.hash AS hash, count(r.hash) AS n FROM objects o
  LEFT JOIN (
    SELECT object_hash AS hash FROM items WHERE object_hash IS NOT NULL
    UNION ALL SELECT conflict_object FROM items WHERE conflict_object IS NOT NULL
    UNION ALL SELECT base_object FROM bindings WHERE base_object IS NOT NULL
    UNION ALL SELECT conflict_object FROM bindings WHERE conflict_object IS NOT NULL
    UNION ALL SELECT shared_object FROM bindings WHERE shared_object IS NOT NULL
    UNION ALL SELECT object_hash FROM queue WHERE object_hash IS NOT NULL
  ) r ON r.hash = o.hash
  GROUP BY o.hash
) AS counted
WHERE counted.hash = objects.hash AND objects.refcount != counted.n;
