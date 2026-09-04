-- Whether a collection holds a live item under a link id: the collision
-- check a queued add runs before staging (§15.3).
SELECT seq FROM items
WHERE collection = :collection AND link_id = :link_id
  AND deleted = 0 AND retained_at IS NULL;
