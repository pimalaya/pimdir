-- Written once, in the transaction that applies 0001_init.sql (§6); the instant
-- is SQLite's (§13), the algorithm the creator's choice (§5), the derivation
-- the Annex A revision the creator derives under.
INSERT INTO store_meta(id, format, version, hash_algo, created_at, derivation)
VALUES(1, 'pimdir', :version, :hash_algo, strftime('%Y-%m-%dT%H:%M:%fZ','now'), :derivation);
