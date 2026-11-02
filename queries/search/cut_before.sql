-- How many calendar items of the query's collections (the `collections`
-- slot) had their occurrences cut before :end, the end of the query's date
-- range, NULL for a range open there (§7, §8.2): what the range cannot see.
SELECT count(*) FROM placement
WHERE collection IN (SELECT value FROM temp.param WHERE slot = 'collections')
  AND cut IS NOT NULL AND (:end IS NULL OR cut < :end);
