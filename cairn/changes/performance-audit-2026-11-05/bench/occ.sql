CREATE TABLE occurrence (collection TEXT NOT NULL, seq INTEGER NOT NULL, start TEXT NOT NULL, end TEXT NOT NULL);
CREATE INDEX occurrence_by_start ON occurrence(start, end);
CREATE INDEX occurrence_by_item ON occurrence(collection, seq);
-- 300 daily series of one hour across a horizon of 1 year back and 2 forward
-- around 2026-11-05, and 20 week-long events.
WITH RECURSIVE s(n) AS (SELECT 1 UNION ALL SELECT n + 1 FROM s WHERE n < 300),
     d(k) AS (SELECT 0 UNION ALL SELECT k + 1 FROM d WHERE k < 1095)
INSERT INTO occurrence SELECT 'cal', n,
  strftime('%Y-%m-%dT%H:%M:%SZ', '2025-11-05T08:00:00Z', '+' || k || ' days', '+' || (n % 10) || ' hours'),
  strftime('%Y-%m-%dT%H:%M:%SZ', '2025-11-05T09:00:00Z', '+' || k || ' days', '+' || (n % 10) || ' hours')
FROM s, d;
INSERT INTO occurrence SELECT 'cal', 1000 + n, strftime('%Y-%m-%dT%H:%M:%SZ', '2026-01-01T00:00:00Z', '+' || (n * 30) || ' days'),
  strftime('%Y-%m-%dT%H:%M:%SZ', '2026-01-01T00:00:00Z', '+' || (n * 30 + 7) || ' days')
FROM (WITH RECURSIVE s(n) AS (SELECT 1 UNION ALL SELECT n + 1 FROM s WHERE n < 20) SELECT n FROM s);
ANALYZE;
SELECT count(*) AS occurrences FROM occurrence;
.timer on
SELECT 'canonical occurrences_between, the week of 2026-11-09', count(*) FROM (SELECT collection, seq, start, end FROM occurrence
WHERE start < '2026-11-16T00:00:00Z' AND (end > '2026-11-09T00:00:00Z' OR start >= '2026-11-09T00:00:00Z')
ORDER BY start, seq, collection);
SELECT 'bounded by the longest span (7 days), same week', count(*) FROM (SELECT collection, seq, start, end FROM occurrence
WHERE start >= '2026-11-02T00:00:00Z' AND start < '2026-11-16T00:00:00Z' AND (end > '2026-11-09T00:00:00Z' OR start >= '2026-11-09T00:00:00Z')
ORDER BY start, seq, collection);
.timer off
EXPLAIN QUERY PLAN SELECT collection, seq, start, end FROM occurrence
WHERE start < '2026-11-16T00:00:00Z' AND (end > '2026-11-09T00:00:00Z' OR start >= '2026-11-09T00:00:00Z') ORDER BY start, seq, collection;
