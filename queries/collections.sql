-- pimdir collections: the container rows (mailboxes, address books, calendars)
-- and their cross-source conflict policy.
--
-- Canonical reference statements servicing the store operations (SPEC.md §12).
-- An implementation SHOULD use them verbatim and MAY substitute an equivalent
-- that preserves the same invariants (SPEC.md §8). Column encodings are in
-- SPEC.md §11. Named parameters use `:name`.

-- name: ensure_collection
-- Guarantee the FK target exists before a source, item or checkpoint write.
INSERT INTO collections(id, kind, name) VALUES(:collection, '', :collection)
ON CONFLICT(id) DO NOTHING;

-- name: set_conflict
UPDATE collections SET conflict = :conflict WHERE id = :collection;

-- name: load_conflict
SELECT conflict FROM collections WHERE id = :collection;

-- name: bump_generation
-- The owner's handle-space reset marker (SPEC.md §15): run in the same
-- transaction as the rebuild it records.
UPDATE collections SET generation = generation + 1 WHERE id = :collection
RETURNING generation;

-- name: load_generation
SELECT generation FROM collections WHERE id = :collection;
