-- A binding's base flag write, on retain_flags' terms: drops every base flag
-- the `flags` slot does not name, add_base_flags then adding the rest.
DELETE FROM binding_base_flag
WHERE collection = :collection AND link_id = :link_id AND source = :source
  AND flag NOT IN (SELECT value FROM temp.param WHERE slot = 'flags');
