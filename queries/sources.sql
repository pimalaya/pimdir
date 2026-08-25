-- pimdir sources: one row per source that syncs a collection, carrying that
-- source's opaque sync cursor (checkpoint).
--
-- Canonical reference statements servicing the store operations (SPEC.md §14).
-- An implementation SHOULD use them verbatim and MAY substitute an equivalent
-- that preserves the same invariants (SPEC.md §7). Column encodings are in
-- SPEC.md §13. Named parameters use `:name`.

-- name: load_checkpoint
-- One source's sync cursor for a collection.
SELECT checkpoint FROM sources WHERE collection = :collection AND source = :source;

-- name: upsert_checkpoint
INSERT INTO sources(collection, source, checkpoint) VALUES(:collection, :source, :checkpoint)
ON CONFLICT(collection, source) DO UPDATE SET checkpoint = excluded.checkpoint;
