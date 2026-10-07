-- Closes the open round in the write after the last chunk of its last page
-- (SYNC.md §5): the checkpoint it carries (:checkpoint, else the one a page
-- landed, else none, the old one kept) becomes the source's, the coverage
-- becomes :since and :until as the engine computed it (the round's scope, or
-- the span a band round widened the old coverage to), stamped now, and the
-- round's columns are cleared. The round id stays, the next round drawing
-- above it.
UPDATE sources SET
    checkpoint = coalesce(:checkpoint, round_checkpoint, checkpoint),
    covered_since = :since, covered_until = :until,
    covered_at = strftime('%Y-%m-%dT%H:%M:%fZ','now'),
    round_since = NULL, round_until = NULL, round_cursor = NULL,
    round_checkpoint = NULL, round_started_at = NULL, round_band = 0
WHERE collection = :collection AND source = :source AND round_started_at IS NOT NULL;
