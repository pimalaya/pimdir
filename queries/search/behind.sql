-- How far the index lags the store (§8.2): the stamps the store drew above the
-- cursor this index folded in, store-wide, 0 when it has folded every change.
SELECT max(0, (SELECT next_change - 1 FROM store.store_meta WHERE id = 1) - store_change)
FROM index_meta WHERE id = 1;
