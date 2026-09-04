-- What an opener checks first: the marker (§3), the version (§4.2), the hash
-- (§5).
SELECT format, version, hash_algo, created_at, next_seq, next_change, purges
FROM store_meta WHERE id = 1;
