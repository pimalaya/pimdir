-- pimdir queue: the action queue, the write door for every process that is not
-- the store owner (SPEC.md §7, §14).
--
-- Canonical reference statements servicing the store operations (SPEC.md §12).
-- An implementation SHOULD use them verbatim and MAY substitute an equivalent
-- that preserves the same invariants (SPEC.md §8). Column encodings are in
-- SPEC.md §11. Named parameters use `:name`.

-- name: enqueue_action
-- A producer's append. Runs after ensure_collection, in one transaction with
-- the store_object upsert when the payload references a body (SPEC.md §14).
INSERT INTO queue(created_at, producer, collection, action, payload, object_hash)
VALUES(:created_at, :producer, :collection, :action, :payload, :object_hash);

-- name: list_queued_collections
-- The collections with pending work, for the owner's drain loop.
SELECT DISTINCT collection FROM queue WHERE error IS NULL;

-- name: load_pending_actions
-- The owner's drain: a collection's pending (non-parked) actions, in append
-- order. An action whose kind this owner cannot apply is skipped, not parked,
-- so it comes back in this result until an owner that can apply it does
-- (SPEC.md §14.2). A reader MAY run the same statement to overlay pending
-- actions on its item projection (read-your-writes, SPEC.md §14).
SELECT id, created_at, producer, action, payload, object_hash, attempts
FROM queue WHERE collection = :collection AND error IS NULL ORDER BY id;

-- name: delete_action
-- An applied action: deleted in the same transaction as its item and binding
-- writes, so applying is exactly-once.
DELETE FROM queue WHERE id = :id;

-- name: bump_attempts
-- A failed but still retryable action: the attempt counter advances while the
-- row stays pending, so the next drain picks it up again (SPEC.md §14.2).
UPDATE queue SET attempts = attempts + 1 WHERE id = :id;

-- name: park_action
-- A permanently failing action: recorded and skipped, visible to operators and
-- frontends instead of blocking the collection's queue forever.
UPDATE queue SET attempts = :attempts, error = :error WHERE id = :id;

-- name: load_parked_actions
-- The parked actions, for status surfaces and operator repair.
SELECT id, created_at, producer, collection, action, payload, attempts, error
FROM queue WHERE error IS NOT NULL ORDER BY id;

-- name: cancel_action
-- One queue row removed by request rather than by application, pending or
-- parked (SPEC.md §14.5): a queued item withdrawn, or a performed intent
-- acknowledged by the process that could carry it out. The same delete as
-- delete_action, named apart because the trigger is a request, not an apply.
-- It releases the row's object_hash pin, so it MUST run in one transaction with
-- the refcount settle: a body nothing else references then falls to the
-- ordinary sweep (SPEC.md §5, §12).
DELETE FROM queue WHERE id = :id;
