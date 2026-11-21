-- The retained row holding a link id, if any: its public id and the objects
-- it pins, which revive releases and purge reclaims (§11).
SELECT seq, (SELECT o.hash FROM objects o WHERE o.id = items.object) AS object_hash, (SELECT o.hash FROM objects o WHERE o.id = items.conflict_object) AS conflict_object FROM items
WHERE collection = :collection AND link_id = :link_id AND retained_at IS NOT NULL;
