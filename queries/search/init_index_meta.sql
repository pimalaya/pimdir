-- Written once, in the transaction that applies 0001_init.sql (§2): this
-- draft's version and the canonical shape, the version and the tokenizer, and
-- the store the index is built from, read off the attached store, so the
-- index records the very id and incarnation it folds (§4).
INSERT INTO index_meta(id, format_version, shape, version, tokenizer, store_id, store_incarnation)
SELECT 1, 'search-draft-09', 'canonical', :version, :tokenizer, store_id, incarnation
FROM store.store_meta WHERE id = 1;
