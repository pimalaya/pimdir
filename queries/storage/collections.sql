-- pimdir collections: the container rows (mailboxes, address books, calendars)
-- and their cross-source conflict policy.
--
-- Reference statements for the store operations (STORAGE.md §4.4, §14); column
-- encodings in §13, named parameters `:name`.

-- name: ensure_collection
-- Guarantees the FK target exists before a source, item or checkpoint write.
-- Binds the account too, since a collection that appears without one is
-- invisible to every by-account read until it is set.
INSERT INTO collections(id, account, kind, name)
VALUES(:collection, :account, '', :collection)
ON CONFLICT(id) DO NOTHING;

-- name: set_collection_kind
-- Unlike ensure_collection this is deliberate, so it does overwrite a kind
-- already declared; the row's name is untouched.
INSERT INTO collections(id, account, kind, name)
VALUES(:collection, :account, :kind, :collection)
ON CONFLICT(id) DO UPDATE SET kind = excluded.kind;

-- name: set_collection_account
-- Rare: the account is normally set when the collection is first ensured. Safe
-- at any time, because the account partitions no identifier (§9.2): the move
-- regroups the collection and leaves its seqs, link ids and objects alone.
UPDATE collections SET account = :account WHERE id = :collection;

-- name: rename_collection
-- The only safe way to change an id, and where both a server-side rename and an
-- account rename that renamespaced it land (§9.2). Every foreign key onto
-- collections(id) is ON UPDATE CASCADE, so items, sources, bindings, queue rows
-- and children follow in one statement; deleting and recreating instead
-- cascades the delete, turning a rename into a full re-download (§14).
UPDATE collections SET id = :new_id WHERE id = :collection;

-- name: load_account
SELECT account FROM collections WHERE id = :collection;

-- name: load_kind
-- The empty string means the row was created lazily by a sync and no kind was
-- ever declared (§14).
SELECT kind FROM collections WHERE id = :collection;

-- name: set_conflict
UPDATE collections SET conflict = :conflict WHERE id = :collection;

-- name: load_conflict
SELECT conflict FROM collections WHERE id = :collection;

-- name: bump_generation
-- Run in the same transaction as the handle-space rebuild it records (§12).
UPDATE collections SET generation = generation + 1 WHERE id = :collection
RETURNING generation;

-- name: load_generation
SELECT generation FROM collections WHERE id = :collection;

-- The client read surface (§14.1).

-- name: list_collections
-- Ordered by sort_order then id, the ones carrying no sort order last. The
-- merged view reads exactly this and groups on `account`.
SELECT id, account, kind, name, parent, color, description, sort_order, generation
FROM collections ORDER BY sort_order IS NULL, sort_order, id;

-- name: list_collections_by_account
-- `IS` so binding NULL selects the collections of a single-account store.
SELECT id, account, kind, name, parent, color, description, sort_order, generation
FROM collections WHERE account IS :account
ORDER BY sort_order IS NULL, sort_order, id;

-- name: list_accounts
-- A store knows an account only through its collections, account configuration
-- living outside the store (§9.2), so an account with no collection yet is
-- invisible here and that is deliberate.
SELECT DISTINCT account FROM collections WHERE account IS NOT NULL ORDER BY account;

-- The change feed (§4.5): the collections whose row moved since a stamp, a
-- renamed one included.

-- name: list_collections_changed_since
SELECT id, account, kind, name, changed FROM collections
WHERE changed > :since ORDER BY changed LIMIT :limit;
