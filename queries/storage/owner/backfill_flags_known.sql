-- Marks a placement's flag set known during the reconciliation of a store
-- from before the flag tables (§6), before its flags are written with
-- retain_flags and add_flags. A set the earlier draft held as NULL stays
-- unknown, the column's default.
UPDATE items SET flags_known = 1 WHERE collection = :collection AND link_id = :link_id;
