-- The time-based sweep, store-wide since how long to keep is the owner's policy
-- rather than a collection's. The cutoff (RFC 3339) is the caller's parameter,
-- not the store's clock, so the boundary is deterministic even though the stamp
-- is SQLite's. It returns pinned hashes on purge_item's terms.
DELETE FROM items WHERE retained_at IS NOT NULL AND retained_at < :cutoff
RETURNING object_hash, conflict_object;
