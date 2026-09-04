-- Rare: the account is normally set when the collection is first ensured. Safe
-- at any time, because the account partitions no identifier (§9.2): the move
-- regroups the collection and leaves its seqs, link ids and objects alone.
UPDATE collections SET account = :account WHERE id = :collection;
