-- Forgets whether a public id is split (§3), before split_mark records it
-- again: run for each public id a batch placed or dropped, after its
-- placement writes (§4).
DELETE FROM split WHERE seq = :seq;
