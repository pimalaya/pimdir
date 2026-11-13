-- What a refresh checks first (§2, §4): the version and tokenizer, the
-- cursors folded in, the horizon and the time zones the occurrences stand
-- under, the store the index was built from, compared with the store's own,
-- the version and shape of the index, which a query client reads too, and
-- the revisions its bodies were extracted under.
SELECT version, tokenizer, store_change, store_purges, horizon_start, horizon_end, tzdb_version,
       store_id, store_incarnation, format_version, shape, floating_zone, extraction, extractor
FROM index_meta WHERE id = 1;
