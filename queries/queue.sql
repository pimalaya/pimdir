-- pimdir queue: the action queue, the write door for every process that is not
-- the store owner (SPEC.md §8, §15).
--
-- Canonical reference statements servicing the store operations (SPEC.md §14).
-- An implementation SHOULD use them verbatim and MAY substitute an equivalent
-- that preserves the same invariants (SPEC.md §7). Column encodings are in
-- SPEC.md §13. Named parameters use `:name`.

-- name: enqueue_action
-- A producer's append. Runs after ensure_collection, in one transaction with
-- the store_object upsert when the payload references a body (SPEC.md §15).
--
-- created_at is stamped by SQLite, like retained_at (SPEC.md §13), so every
-- implementation writes the same shape and no producer plumbs a clock through
-- to reach it. It is also the better clock: a producer is a different process
-- from the owner and may be differently skewed, while the database has one.
-- Ordering is unaffected either way, being `id`.
INSERT INTO queue(created_at, producer, collection, action, payload, object_hash)
VALUES(strftime('%Y-%m-%dT%H:%M:%fZ','now'), :producer, :collection, :action, :payload, :object_hash);

-- name: list_queued_collections
-- The collections with pending work, for the owner's drain loop.
SELECT DISTINCT collection FROM queue WHERE error IS NULL;

-- name: load_pending_actions
-- The owner's drain: a collection's pending (non-parked) actions, in append
-- order. An action whose kind this owner cannot apply is skipped, not parked,
-- so it comes back in this result until an owner that can apply it does
-- (SPEC.md §15.2). A reader MAY run the same statement to overlay pending
-- actions on its item projection (read-your-writes, SPEC.md §15).
SELECT id, created_at, producer, action, payload, object_hash, attempts
FROM queue WHERE collection = :collection AND error IS NULL ORDER BY id;

-- name: claim_action
-- The row an owner is about to apply, deleted in the same transaction as the
-- item and binding writes it produces, and reporting whether it was still
-- there. It runs FIRST in that transaction, not last: the pending rows are read
-- outside any transaction (load_pending_actions above), so a second owner
-- holding the same list would otherwise apply every action a second time, and
-- `add` and `copy` are not idempotent. Claiming the row before doing its work
-- makes exactly-once a property of the statement rather than a convention about
-- who runs the drain (SPEC.md §15.2). A claim that deletes nothing means
-- another owner got there first: there is nothing left to apply.
DELETE FROM queue WHERE id = :id RETURNING id;

-- name: bump_attempts
-- A failed but still retryable action: the attempt counter advances while the
-- row stays pending, so the next drain picks it up again (SPEC.md §15.2).
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
-- parked (SPEC.md §15.5): a queued item withdrawn, or a performed intent
-- acknowledged by the process that could carry it out. The same delete as
-- claim_action, named apart because the trigger is a request, not an apply.
-- It releases the row's object_hash pin, so it MUST run in one transaction with
-- the refcount settle: a body nothing else references then falls to the
-- ordinary sweep (SPEC.md §5, §14).
DELETE FROM queue WHERE id = :id;
