-- The temporal coverage over every collection of the store (§8.2), what a
-- query no conjunct narrows reads: the highest floor and the lowest ceiling
-- among the sources that closed a round, NULL where none bounds that side,
-- and how many sources never closed one. It answers what list_coverage
-- answers per collection, rolled up over every collection: each value is
-- the end of a partial index on sources, so its cost is three seeks, never
-- the sources.
SELECT (SELECT max(covered_since) FROM store.sources
        WHERE covered_at IS NOT NULL AND covered_since IS NOT NULL) AS since,
       (SELECT min(covered_until) FROM store.sources
        WHERE covered_at IS NOT NULL AND covered_until IS NOT NULL) AS until,
       (SELECT count(*) FROM store.sources WHERE covered_at IS NULL) AS filling;
