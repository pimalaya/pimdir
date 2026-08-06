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

-- name: set_collection_kind
-- Declare a collection's media type (SPEC.md §12), creating the row if the
-- store has not seen it yet. Unlike ensure_collection this is deliberate, so
-- it does overwrite a previously declared kind; the row's name is untouched.
INSERT INTO collections(id, kind, name) VALUES(:collection, :kind, :collection)
ON CONFLICT(id) DO UPDATE SET kind = excluded.kind;

-- name: load_kind
-- A collection's declared media type; the empty string means the row was
-- created lazily by a sync and no kind was ever declared (SPEC.md §12).
SELECT kind FROM collections WHERE id = :collection;

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

-- The client read surface (SPEC.md §12.1).

-- name: list_collections
-- Every collection with its display metadata and handle-space generation,
-- ordered by sort_order then id, the ones carrying no sort order coming last.
SELECT id, kind, name, parent, color, description, sort_order, generation
FROM collections ORDER BY sort_order IS NULL, sort_order, id;
