-- The only true delete, guarded on retained_at so it never takes a live item.
-- It returns the pinned hashes for release_pins in the same transaction, and
-- the delete trigger counts the purge (§4.5, §14).
DELETE FROM items
WHERE collection = :collection AND seq = :seq AND retained_at IS NOT NULL
RETURNING object_hash, conflict_object;
