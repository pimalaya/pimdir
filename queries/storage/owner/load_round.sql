-- The round under way, if any (SYNC.md §5): `round_started_at` NULL is none.
-- `round` is the last id drawn, the one the open round stamps with.
SELECT round, round_started_at, round_since, round_until, round_cursor, round_checkpoint
FROM sources WHERE collection = :collection AND source = :source;
