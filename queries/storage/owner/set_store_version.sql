-- A migration's own stamp (§6): run in the transaction applying it, beside
-- `PRAGMA user_version` set to the same number, so the two never disagree
-- (§4.2). The compatibility versions are the ones the migration states, and
-- the format version follows the schema version. Nothing else moves them.
UPDATE store_meta SET version = :version, read_version = :read_version, produce_version = :produce_version,
                      format_version = 'storage-v' || :version
WHERE id = 1;
