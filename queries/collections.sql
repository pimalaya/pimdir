-- pimdir collections: the container rows (mailboxes, address books, calendars)
-- and their cross-source conflict policy.
--
-- Canonical reference statements servicing the store operations (SPEC.md §12).
-- An implementation SHOULD use them verbatim and MAY substitute an equivalent
-- that preserves the same invariants (SPEC.md §8). Column encodings are in
-- SPEC.md §11. Named parameters use `:name`.

-- name: ensure_collection
-- Guarantee the FK target exists before a source, item or checkpoint write.
-- Binds the account (NULL in a single-account store) so the row is grouped from
-- the moment it exists; a collection that appears without one is invisible to
-- every by-account read until it is set.
INSERT INTO collections(id, account, kind, name)
VALUES(:collection, :account, '', :collection)
ON CONFLICT(id) DO NOTHING;

-- name: set_collection_kind
-- Declare a collection's media type (SPEC.md §12), creating the row if the
-- store has not seen it yet. Unlike ensure_collection this is deliberate, so
-- it does overwrite a previously declared kind; the row's name is untouched.
INSERT INTO collections(id, account, kind, name)
VALUES(:collection, :account, :kind, :collection)
ON CONFLICT(id) DO UPDATE SET kind = excluded.kind;

-- name: set_collection_account
-- Move a collection into an account, or out of one with a NULL. Rare: the
-- account is normally set when the collection is first ensured. Safe at any
-- time, because the account partitions no identifier (SPEC.md §9.2): the move
-- regroups the collection and leaves its seqs, link ids and objects alone.
UPDATE collections SET account = :account WHERE id = :collection;

-- name: load_account
SELECT account FROM collections WHERE id = :collection;

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
-- Every collection with its account, display metadata and handle-space
-- generation, ordered by sort_order then id, the ones carrying no sort order
-- coming last. The merged view reads exactly this and groups on `account`.
SELECT id, account, kind, name, parent, color, description, sort_order, generation
FROM collections ORDER BY sort_order IS NULL, sort_order, id;

-- name: list_collections_by_account
-- One account's collections, the filter axis of a merged view (SPEC.md §9.2).
-- `IS` so binding NULL selects the collections of a single-account store.
SELECT id, account, kind, name, parent, color, description, sort_order, generation
FROM collections WHERE account IS :account
ORDER BY sort_order IS NULL, sort_order, id;

-- name: list_accounts
-- The accounts that own at least one collection. A store knows an account only
-- through its collections: account configuration (credentials, endpoints,
-- display name) lives outside the store (SPEC.md §9.2), so an account with no
-- collection yet is invisible here and that is deliberate.
SELECT DISTINCT account FROM collections WHERE account IS NOT NULL ORDER BY account;
