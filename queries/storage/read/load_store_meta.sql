-- What an opener checks first: the marker (§3), the version (§4.2, §6), the
-- hash (§5); then the Annex A revision the rows were derived under (§6).
SELECT format, version, hash_algo, created_at, next_seq, next_change, purges, derivation
FROM store_meta WHERE id = 1;
