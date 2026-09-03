-- pimdir sources: one row per source syncing a collection, carrying that
-- source's opaque sync cursor.
--
-- Reference statements for the store operations (STORAGE.md §4.4, §14); column
-- encodings in §13, named parameters `:name`.

-- name: load_checkpoint
SELECT checkpoint FROM sources WHERE collection = :collection AND source = :source;

-- name: upsert_checkpoint
INSERT INTO sources(collection, source, checkpoint) VALUES(:collection, :source, :checkpoint)
ON CONFLICT(collection, source) DO UPDATE SET checkpoint = excluded.checkpoint;
