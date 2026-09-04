-- The bytes are in the blob file already, written by this batch or streamed
-- there beforehand; the refcount is settled later in the batch (§14).
INSERT INTO objects(hash, size, refcount) VALUES(:hash, :size, 0)
ON CONFLICT(hash) DO UPDATE SET size = excluded.size;
