SELECT version, tokenizer, store_change, store_purges, horizon_start, horizon_end, tzdb_version,
       store_reconciled
FROM index_meta WHERE id = 1;
