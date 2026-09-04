-- The update that replaces the delete a hard-deleting store would issue. The
-- row keeps its object_hash, so the body stays pinned against the collector
-- (§5). SQLite stamps the instant; the cutoff of a later purge is the caller's.
UPDATE items SET deleted = 1,
                 retained_at = strftime('%Y-%m-%dT%H:%M:%fZ','now'),
                 retained_by = :source
WHERE collection = :collection AND link_id = :link_id;
