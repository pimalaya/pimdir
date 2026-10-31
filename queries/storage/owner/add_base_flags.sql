INSERT INTO binding_base_flag(collection, link_id, source, flag)
SELECT :collection, :link_id, :source, value FROM temp.param WHERE slot = 'flags'
ON CONFLICT DO NOTHING;
