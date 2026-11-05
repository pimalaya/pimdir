INSERT INTO binding_base_flag(item, source, flag)
SELECT (SELECT id FROM items WHERE collection = :collection AND link_id = :link_id), :source, value
FROM temp.param WHERE slot = 'flags'
ON CONFLICT DO NOTHING;
