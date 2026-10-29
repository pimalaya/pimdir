-- Records that an `add` superseded an item (§15.3), in the transaction that
-- applies the add and tombstones the item: the item at :collection and
-- :link_id, the add's at :by_collection and :by_link_id. A second add
-- superseding the same item replaces the pair.
INSERT INTO supersessions (collection, link_id, by_collection, by_link_id)
VALUES (:collection, :link_id, :by_collection, :by_link_id)
ON CONFLICT (collection, link_id) DO UPDATE
SET by_collection = excluded.by_collection, by_link_id = excluded.by_link_id;
