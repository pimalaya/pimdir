-- Every calendar placement with an occurrence overlapping [:start, :end).
SELECT DISTINCT collection, seq FROM occurrence WHERE start < :end AND end > :start;
