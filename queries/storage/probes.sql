-- pimdir probes: handles a source enumerated whose identity is not read yet
-- (STORAGE.md §4.4, SYNC.md §3). Named in one transaction: item and binding in,
-- probe out.
--
-- Reference statements for the store operations (STORAGE.md §4.4, §14); column
-- encodings in §13, named parameters `:name`.

-- name: load_probes
-- One source's unnamed handles, read beside the named ones (SYNC.md §3).
SELECT handle, flags FROM probes WHERE collection = :collection AND source = :source;

-- name: upsert_probe
-- Unknown markers (NULL) never erase known ones (§13).
INSERT INTO probes(collection, source, handle, flags)
VALUES(:collection, :source, :handle, :flags)
ON CONFLICT(collection, source, handle) DO UPDATE SET
    flags = coalesce(excluded.flags, probes.flags);

-- name: delete_probe
-- When the handle is named, dropped by its source, or superseded.
DELETE FROM probes WHERE collection = :collection AND source = :source AND handle = :handle;

-- name: delete_probes
-- A handle-space rebuild (§12) voids every unnamed handle at once.
DELETE FROM probes WHERE collection = :collection AND source = :source;

-- name: count_probes
-- How much of a collection a reader cannot list yet.
SELECT count(*) FROM probes WHERE collection = :collection;
