-- The sources syncing one collection, by a binding or a checkpoint of their
-- own, so a run knows whether it syncs beside others (SYNC §5): a source
-- whose remote dropped its last member keeps its checkpoint.
SELECT source FROM sources WHERE collection = :collection
UNION
SELECT source FROM bindings WHERE collection = :collection;
