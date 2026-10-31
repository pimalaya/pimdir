-- The version of SYNC.md whose engine writes the sync state (§14): set in
-- the transaction of an engine's first write, and when an engine of another
-- version takes the store over as the sync part allows (SYNC.md §10). Nothing
-- else moves it.
UPDATE store_meta SET sync_version = :sync_version WHERE id = 1;
