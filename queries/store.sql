-- pimdir store_meta: the one row that fixes the store's format, hash and
-- counters (STORAGE.md §4.2, §4.5).
--
-- Reference statements for the store operations (STORAGE.md §4.4, §14); column
-- encodings in §13, named parameters `:name`.

-- name: init_store_meta
-- Written once, in the transaction that applies the schema; the instant is
-- SQLite's (§13), the algorithm the creator's choice (§5).
INSERT INTO store_meta(id, format, version, hash_algo, created_at)
VALUES(1, 'pimdir', :version, :hash_algo, strftime('%Y-%m-%dT%H:%M:%fZ','now'));

-- name: load_store_meta
-- What an opener checks first: the marker (§3), the version (§4.2), the hash
-- (§5).
SELECT format, version, hash_algo, created_at, next_seq, next_change, purges
FROM store_meta WHERE id = 1;
