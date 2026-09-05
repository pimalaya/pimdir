-- Asks for a stamp on an item whose summary or addresses moved while its own
-- columns did not (§4.5): the triggers cannot see those tables. The request
-- trigger draws the stamp and bumps the counter, so no writer reads one.
UPDATE items SET changed = -1
WHERE collection = :collection AND link_id = :link_id;
