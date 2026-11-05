-- The second half of retain_flags: adds every flag the `flags` slot names that
-- the placement lacks, a flag named twice once.
INSERT INTO placement_flag(item, flag)
SELECT (SELECT id FROM items WHERE collection = :collection AND link_id = :link_id), value
FROM temp.param WHERE slot = 'flags'
ON CONFLICT DO NOTHING;
