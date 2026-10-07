-- Opens a round over the scope :since and :until (NULL bounds open), in the
-- write of its first page (SYNC.md §5). It draws the next round id, so a
-- round restarted after the source refused its cursor stamps afresh and the
-- stamps of the abandoned listing name nothing; the cursor and the checkpoint
-- of an earlier attempt go with it. The checkpoint and the coverage stay
-- until the round closes.
INSERT INTO sources(collection, source, round, round_since, round_until, round_started_at)
VALUES(:collection, :source, 1, :since, :until, strftime('%Y-%m-%dT%H:%M:%fZ','now'))
ON CONFLICT(collection, source) DO UPDATE SET
    round = sources.round + 1,
    round_since = excluded.round_since, round_until = excluded.round_until,
    round_cursor = NULL, round_checkpoint = NULL,
    round_started_at = excluded.round_started_at;
