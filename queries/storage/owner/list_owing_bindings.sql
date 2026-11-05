-- The handles of a source's bindings in a collection whose placement may owe
-- a push or a decision (SYNC.md §3, §10): its binding or its item conflicted,
-- its item deleted, no base, its flag set known on both sides and differing
-- (the system flags' bits, then the other flags' rows), or an object other
-- than its base's. A superset of the placements not Clean, since the
-- projection still decides each status from the rows a load reads: a delta
-- loads these handles beside those it lists, rather than the whole
-- collection. Seeks bindings_by_handle on the collection and the source, and
-- each item by its id.
SELECT b.handle FROM bindings b JOIN items i ON i.id = b.item
WHERE b.collection = :collection AND b.source = :source
  AND (b.conflicted = 1 OR i.conflicted = 1 OR i.deleted = 1
       OR NOT (b.base_present = 1 OR b.base_flags_known = 1
               OR b.base_object IS NOT NULL OR b.base_revision IS NOT NULL)
       OR (i.flags_known = 1 AND b.base_flags_known = 1
           AND (i.marks != b.base_marks
                OR EXISTS (SELECT flag FROM placement_flag f WHERE f.item = i.id
                           EXCEPT
                           SELECT flag FROM binding_base_flag g
                           WHERE g.item = b.item AND g.source = b.source)
                OR EXISTS (SELECT flag FROM binding_base_flag g
                           WHERE g.item = b.item AND g.source = b.source
                           EXCEPT
                           SELECT flag FROM placement_flag f WHERE f.item = i.id)))
       OR (i.object_hash IS NOT NULL AND i.object_hash IS NOT b.base_object))
ORDER BY b.handle;
