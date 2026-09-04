-- Retained items excluded: the sync seam sees live items only, and hiding them
-- here is what keeps one from being re-derived on a later sync (§11).
-- `sort_key` rides along although the sync layer has no use for it: a write
-- carries it back unchanged unless it restates it (§9.3).
SELECT link_id, flags, object_hash, sort_key, level, deleted, conflicted, conflict_object
FROM items WHERE collection = :collection AND retained_at IS NULL;
