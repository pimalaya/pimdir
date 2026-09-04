-- The O(changes) alternative to recompute_refcounts, for an implementation that
-- diffs its writes (§14).
UPDATE objects SET refcount = refcount + :delta WHERE hash = :hash;
