-- Recount from the six pointers that pin an object in one grouped pass, linear
-- in the pointers (§7): a correlated subquery per object would be quadratic,
-- the OR across `object` and conflict_object being a disjunction no index
-- serves. The left join is what settles an object no pointer names any more,
-- counting zero rather than leaving it unvisited (§5). Every pointer is the
-- object's id, so the pass joins integers and never reads a hash.
UPDATE objects SET refcount = counted.n
FROM (
  SELECT o.id AS id, count(r.object) AS n FROM objects o
  LEFT JOIN (
    SELECT object FROM items WHERE object IS NOT NULL
    UNION ALL SELECT conflict_object FROM items WHERE conflict_object IS NOT NULL
    UNION ALL SELECT base_object FROM bindings WHERE base_object IS NOT NULL
    UNION ALL SELECT conflict_object FROM bindings WHERE conflict_object IS NOT NULL
    UNION ALL SELECT shared_object FROM bindings WHERE shared_object IS NOT NULL
    UNION ALL SELECT object FROM queue WHERE object IS NOT NULL
  ) r ON r.object = o.id
  GROUP BY o.id
) AS counted
WHERE counted.id = objects.id AND objects.refcount != counted.n;
