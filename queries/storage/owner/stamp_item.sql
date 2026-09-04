-- Stamps an item whose summary or addresses moved while its own columns did
-- not (§4.5); the triggers cannot see those tables.
UPDATE items SET changed = (SELECT next_change FROM store_meta WHERE id = 1)
WHERE collection = :collection AND link_id = :link_id;
