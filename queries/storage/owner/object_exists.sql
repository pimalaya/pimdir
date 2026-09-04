-- Asked once per file as the collector walks the blob directory, after
-- delete_garbage_objects has committed, so one pass reclaims the collected and
-- the orphaned together. A point lookup rather than list_object_hashes, which
-- would hold the whole index in memory to answer about one file (§5).
SELECT 1 FROM objects WHERE hash = :hash;
