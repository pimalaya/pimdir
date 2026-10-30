-- A migration's own stamp (§6): run in the transaction applying it, beside
-- `PRAGMA user_version` set to the same number, so the two never disagree
-- (§4.2). Nothing else moves the version.
UPDATE store_meta SET version = :version WHERE id = 1;
