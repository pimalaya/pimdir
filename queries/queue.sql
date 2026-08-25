-- pimdir queue: the action queue, the write door for every process that is not
-- the store owner (SPEC.md §8, §15).
--
-- Reference statements for the store operations (SPEC.md §4.4, §14); column
-- encodings in §13, named parameters `:name`.

-- name: enqueue_action
-- A producer's append. Runs after ensure_collection, in one transaction with
-- the store_object upsert when the payload references a body (§15). SQLite
-- stamps created_at (§13): the producer is a different process from the owner
-- and may be differently skewed, and ordering is `id` either way.
INSERT INTO queue(created_at, producer, collection, action, payload, object_hash)
VALUES(strftime('%Y-%m-%dT%H:%M:%fZ','now'), :producer, :collection, :action, :payload, :object_hash);

-- name: list_queued_collections
-- The collections with pending work, for the owner's drain loop.
SELECT DISTINCT collection FROM queue WHERE error IS NULL;

-- name: load_pending_actions
-- The owner's drain. An action whose kind this owner cannot apply is skipped,
-- not parked, so it comes back here until an owner that can apply it does
-- (§15.2). A reader MAY run it to overlay pending actions on its projection.
SELECT id, created_at, producer, action, payload, object_hash, attempts
FROM queue WHERE collection = :collection AND error IS NULL ORDER BY id;

-- name: claim_action
-- Runs FIRST in the transaction that applies the action, not last: the pending
-- rows are read outside any transaction, so a second owner holding the same
-- list would otherwise apply every one twice, and `add` and `copy` are not
-- idempotent. A claim that deletes nothing means another owner got there
-- first (§15.2).
DELETE FROM queue WHERE id = :id RETURNING id;

-- name: bump_attempts
-- A failed but still retryable action: the row stays pending, so the next drain
-- picks it up again (§15.2).
UPDATE queue SET attempts = attempts + 1 WHERE id = :id;

-- name: park_action
-- A permanently failing action: recorded and skipped, visible to operators
-- instead of blocking the collection's queue for ever.
UPDATE queue SET attempts = :attempts, error = :error WHERE id = :id;

-- name: load_parked_actions
SELECT id, created_at, producer, collection, action, payload, attempts, error
FROM queue WHERE error IS NOT NULL ORDER BY id;

-- name: cancel_action
-- Removal by request rather than by application (§15.5): a queued item
-- withdrawn, or an intent acknowledged by the process that carried it out. It
-- releases the row's object_hash pin, so it MUST run in one transaction with
-- the refcount settle (§5, §14).
DELETE FROM queue WHERE id = :id;
