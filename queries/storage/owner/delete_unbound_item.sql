-- Deletes an item no source binds (§14.3): a file of a folder on the device,
-- or a stand-in, which no sync removes and no retention keeps. A bound item
-- is refused (no row): its source removes it. Returns the hashes it pinned,
-- for release_pins in the same transaction.
DELETE FROM items
WHERE collection = :collection AND link_id = :link_id
  AND NOT EXISTS (SELECT 1 FROM bindings b
                  WHERE b.collection = items.collection AND b.link_id = items.link_id)
RETURNING object_hash, conflict_object;
