-- A failed but still retryable action: the row stays pending, so the next drain
-- picks it up again (§15.2).
UPDATE queue SET attempts = attempts + 1 WHERE id = :id;
