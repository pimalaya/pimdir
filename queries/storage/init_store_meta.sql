-- Written once, in the transaction that applies the schema; the instant is
-- SQLite's (§13), the algorithm the creator's choice (§5).
INSERT INTO store_meta(id, format, version, hash_algo, created_at)
VALUES(1, 'pimdir', :version, :hash_algo, strftime('%Y-%m-%dT%H:%M:%fZ','now'));
