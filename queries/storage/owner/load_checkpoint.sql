-- The checkpoint with the coverage it serves (SYNC.md §5): a checkpoint
-- serves the scope it was made under and any scope inside it, so a run reads
-- both before choosing a delta or a round. `covered_at` NULL is never
-- complete; a checkpoint from an earlier draft has no coverage and was made
-- under no scope.
SELECT checkpoint, covered_since, covered_until, covered_at
FROM sources WHERE collection = :collection AND source = :source;
