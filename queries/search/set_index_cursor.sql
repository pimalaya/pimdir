-- Written in the transaction that folded the changes it names (§4): a batch
-- passes the purge count and store_reconciled the last completed pass
-- recorded, a completing pass the cursor it read before it began as both
-- store_change and store_reconciled.
UPDATE index_meta SET store_change = :store_change, store_purges = :store_purges,
                      store_reconciled = :store_reconciled
WHERE id = 1;
