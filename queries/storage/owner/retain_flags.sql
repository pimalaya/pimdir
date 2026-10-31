-- The first half of a placement's flag write (§13): drops every flag the
-- `flags` slot does not name, add_flags then adding the rest, both after the
-- item's row is written. An unknown set binds the slot empty. A flag that
-- moves requests the stamp (§4.5); a set written as it was moves none.
DELETE FROM placement_flag
WHERE collection = :collection AND link_id = :link_id
  AND flag NOT IN (SELECT value FROM temp.param WHERE slot = 'flags');
