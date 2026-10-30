-- Every calendar placement with an occurrence overlapping [:start, :end): one
-- starting before the range ends and ending after it starts, or one of zero
-- length starting inside it, a task due at the range's first instant included
-- (SEARCH.md §8.1).
SELECT DISTINCT collection, seq FROM occurrence
WHERE start < :end AND (end > :start OR start >= :start);
