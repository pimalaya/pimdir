-- Every item stamped above :since, retained ones included: a retention is a
-- change a mirror has to see (§11).
SELECT collection, link_id, seq, changed, deleted, retained_at
FROM items WHERE changed > :since
ORDER BY changed LIMIT :limit;
