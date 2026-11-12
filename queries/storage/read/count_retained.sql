-- The counterpart of count_items, riding the items_deleted partial index.
SELECT count(*) AS count FROM items WHERE collection = :collection AND deleted = 1;
