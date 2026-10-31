-- Writes the target a pending row's payload names (a move or copy `to`, a
-- superseding add's `supersedes.collection`) into a queue rebuilt with
-- target_collection (§6), one row at a time, the owner reading the payload.
UPDATE queue SET target_collection = :target_collection WHERE id = :id;
