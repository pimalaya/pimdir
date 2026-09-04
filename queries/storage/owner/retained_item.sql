-- The retained row holding a link id, if any: its public id and the objects
-- it pins, which revive releases and purge reclaims (§11).
SELECT seq, object_hash, conflict_object FROM items
WHERE collection = :collection AND link_id = :link_id AND retained_at IS NOT NULL;
