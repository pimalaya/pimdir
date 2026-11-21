-- The handles of a source's bindings in a collection whose placement may owe
-- a push or a decision (SYNC.md §3, §10): those the owing mark holds (STORAGE
-- §4.6), its binding or its item conflicted, its item deleted, no base, its
-- flag set known on both sides and differing, or an object other than its
-- base's. A superset of the placements not Clean, since the projection still
-- decides each status from the rows a load reads: a delta loads these handles
-- beside those it lists, rather than the whole collection. Seeks
-- bindings_owing, which holds what is owed alone, in handle order.
SELECT handle FROM bindings
WHERE collection = :collection AND source = :source AND owes = 1
ORDER BY handle;
