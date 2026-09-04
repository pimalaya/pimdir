-- One source's binding of an item, dropped as Deleted while others remain.
DELETE FROM bindings WHERE collection = :collection AND link_id = :link_id AND source = :source;
