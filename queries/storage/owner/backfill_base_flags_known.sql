-- backfill_flags_known for a binding's base, before retain_base_flags and
-- add_base_flags.
UPDATE bindings SET base_flags_known = 1
WHERE collection = :collection AND link_id = :link_id AND source = :source;
