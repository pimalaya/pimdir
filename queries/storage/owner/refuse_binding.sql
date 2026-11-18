-- Records a refusal (SYNC.md §4, §5): the remote refused for good the change
-- keyed :key that this source pushed for its binding under :handle, giving
-- :reason, scrubbed of credentials first (§18). It replaces a refusal standing
-- there, SQLite stamping refused_at, in the write recording the outcome. No
-- binding under that handle (a create withdrawn or landed since) records
-- nothing; an engine binds a create the store offered first (SYNC.md §5).
-- Seeks bindings_by_handle.
UPDATE bindings SET refusal = :reason, refused_key = :key,
       refused_at = strftime('%Y-%m-%dT%H:%M:%fZ','now')
WHERE collection = :collection AND source = :source AND handle = :handle;
