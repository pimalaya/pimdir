-- The counterpart of count_items, riding the items_retained partial index.
SELECT count(*) FROM items WHERE collection = :collection AND retained_at IS NOT NULL;
