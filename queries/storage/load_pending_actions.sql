-- The owner's drain. An action whose kind this owner cannot apply is skipped,
-- not parked, so it comes back here until an owner that can apply it does
-- (§15.2). A reader MAY run it to overlay pending actions on its projection.
SELECT id, created_at, producer, action, payload, object_hash, attempts
FROM queue WHERE collection = :collection AND error IS NULL ORDER BY id;
