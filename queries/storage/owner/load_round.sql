-- The round under way, if any (SYNC.md §5): `round_started_at` NULL is none.
-- `round` is the last id drawn, the one the open round stamps with;
-- `round_band` 1 is a round listing only the band the coverage lacks.
SELECT round, round_started_at, round_since, round_until, round_cursor, round_checkpoint, round_band
FROM sources WHERE collection = :collection AND source = :source;
