-- Records that an `add` superseded an item (§15.3), in the transaction that
-- applies the add and tombstones the item: the item at :collection and
-- :link_id, the add's at :by_collection and :by_link_id. A second add
-- superseding the same item replaces the pair.
INSERT INTO supersessions (item, by_item)
VALUES ((SELECT id FROM items WHERE collection = :collection AND link_id = :link_id),
        (SELECT id FROM items WHERE collection = :by_collection AND link_id = :by_link_id))
ON CONFLICT (item) DO UPDATE SET by_item = excluded.by_item;
