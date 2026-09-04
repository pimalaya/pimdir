-- Every binding of an item, for the retire path (§11): the row survives,
-- and no source holds it.
DELETE FROM bindings WHERE collection = :collection AND link_id = :link_id;
