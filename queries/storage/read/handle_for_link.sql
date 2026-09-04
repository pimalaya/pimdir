-- One source's handle for an item, the inverse of link_for_handle.
SELECT handle FROM bindings
WHERE collection = :collection AND link_id = :link_id AND source = :source;
