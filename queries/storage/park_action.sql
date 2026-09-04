-- A permanently failing action: recorded and skipped, visible to operators
-- instead of blocking the collection's queue for ever.
UPDATE queue SET attempts = :attempts, error = :error WHERE id = :id;
