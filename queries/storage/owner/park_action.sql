-- A permanently failing action: the attempt counted, the error recorded, the
-- row skipped and visible to operators instead of blocking the collection's
-- queue for ever.
UPDATE queue SET attempts = attempts + 1, error = :error WHERE id = :id;
