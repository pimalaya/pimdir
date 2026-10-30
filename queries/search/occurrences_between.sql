-- Every occurrence overlapping [:start, :end), one row each, on
-- occurring_between's rule: one starting before the range ends and ending
-- after it starts, or one of zero length starting inside it (SEARCH.md §7).
-- In time order, so an agenda reads a window as it shows it.
SELECT collection, seq, start, end FROM occurrence
WHERE start < :end AND (end > :start OR start >= :start)
ORDER BY start, seq, collection;
