-- Run in the same transaction as the handle-space rebuild it records (§12).
UPDATE collections SET generation = generation + 1 WHERE id = :collection
RETURNING generation;
