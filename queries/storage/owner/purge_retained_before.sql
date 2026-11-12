-- The time-based sweep, store-wide since how long to keep is the owner's policy
-- rather than a collection's. The cutoff, :before (RFC 3339, written with its
-- milliseconds as the stamps are, §11.2), is the caller's parameter,
-- not the store's clock, so the boundary is deterministic even though the stamp
-- is SQLite's. A seek below the cutoff on items_by_retained, so a sweep reads
-- what it purges. It returns pinned hashes on purge_item's terms.
DELETE FROM items WHERE retained_at IS NOT NULL AND retained_at < :before
RETURNING object_hash, conflict_object;
