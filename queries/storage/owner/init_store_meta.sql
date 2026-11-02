-- Written once, in the transaction that applies 0001_init.sql (§6): the
-- format version is this draft's (§4.2), the three schema versions the
-- store's, the id 16 random bytes in lowercase hex and the incarnation 1
-- (§4.5), the algorithm the one §5 names, the instant SQLite's (§13), the
-- derivation the Annex A revision the creator derives under.
INSERT INTO store_meta(id, format, format_version, version, read_version, produce_version, store_id,
                       incarnation, hash_algo, created_at, derivation)
VALUES(1, 'pimdir', 'storage-draft-08', :version, :version, :version, lower(hex(randomblob(16))),
       1, 'blake3', strftime('%Y-%m-%dT%H:%M:%fZ','now'), :derivation);
