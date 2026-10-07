-- `IS` so binding NULL selects the collections of a single-account store.
-- The coverage as list_collections reads it.
SELECT c.id, c.account, c.kind, c.name, c.parent, c.color, c.description, c.sort_order,
       c.generation, c.role, v.covered_since, v.covered_until, v.covered_at
FROM collections c
LEFT JOIN (SELECT collection, max(covered_since) AS covered_since,
                  min(covered_until) AS covered_until, min(covered_at) AS covered_at
           FROM sources GROUP BY collection HAVING count(*) = count(covered_at)) v
       ON v.collection = c.id
WHERE c.account IS :account
ORDER BY c.sort_order IS NULL, c.sort_order, c.id;
