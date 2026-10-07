-- Restates the scope a coverage holds, `covered_at` unchanged: a run under a
-- scope inside the coverage needs no round, the checkpoint serving it, and
-- records the narrower coverage it now maintains (SYNC.md §5). Only a closing
-- round (close_round) widens a coverage or stamps it.
UPDATE sources SET covered_since = :since, covered_until = :until
WHERE collection = :collection AND source = :source AND covered_at IS NOT NULL;
