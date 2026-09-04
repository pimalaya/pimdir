-- Clears a collection before it is re-saved, sparing retained rows as
-- load_items skips them (§11). No longer the reference form (§14): it
-- re-inserts every row and so stamps the whole collection on every sync.
DELETE FROM items WHERE collection = :collection AND retained_at IS NULL;
