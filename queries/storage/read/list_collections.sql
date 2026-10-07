-- Ordered by sort_order then id, the ones carrying no sort order last. The
-- merged view reads exactly this and groups on `account`. The coverage is the
-- narrowest of the collection's sources (§14.1): the latest floor, the
-- earliest ceiling and the oldest closing, and none at all while one source
-- has never closed a round.
SELECT c.id, c.account, c.kind, c.name, c.parent, c.color, c.description, c.sort_order,
       c.generation, c.role, v.covered_since, v.covered_until, v.covered_at
FROM collections c
LEFT JOIN (SELECT collection, max(covered_since) AS covered_since,
                  min(covered_until) AS covered_until, min(covered_at) AS covered_at
           FROM sources GROUP BY collection HAVING count(*) = count(covered_at)) v
       ON v.collection = c.id
ORDER BY c.sort_order IS NULL, c.sort_order, c.id;
