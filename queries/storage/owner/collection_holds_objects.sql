-- Whether a collection's rows point at an object (§14): an item's body or
-- conflict, a binding's base or conflict, a queued body. A delete_collection
-- of one that holds none drops no pointer, and recompute_refcounts may be
-- skipped.
SELECT EXISTS (SELECT 1 FROM items WHERE collection = :collection
                 AND (object_hash IS NOT NULL OR conflict_object IS NOT NULL))
    OR EXISTS (SELECT 1 FROM bindings WHERE collection = :collection
                 AND (base_object IS NOT NULL OR conflict_object IS NOT NULL))
    OR EXISTS (SELECT 1 FROM queue WHERE collection = :collection AND object_hash IS NOT NULL);
