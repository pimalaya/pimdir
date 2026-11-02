-- What an opener checks first: the marker (§3), the format version and the
-- versions (§4.2, §6), the hash (§5); then the Annex A revision the rows were
-- derived under (§6), the store's identity (§4.5) and the version of the sync
-- part its sync state follows (§14). A store lacking a column this names was
-- written under an earlier draft, and refused.
SELECT format, version, hash_algo, created_at, next_seq, next_change, purges, derivation,
       format_version, read_version, produce_version, store_id, incarnation, sync_version
FROM store_meta WHERE id = 1;
