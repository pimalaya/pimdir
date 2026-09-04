-- Written in the transaction that folded the changes it names (§4).
UPDATE index_meta SET store_change = :store_change, store_purges = :store_purges WHERE id = 1;
