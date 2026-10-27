-- The chunks of one body in text order (§6), for the snippet of a hit shown.
SELECT c.ord, c.field, c.start, c.end FROM chunk c JOIN object o ON o.id = c.object
WHERE o.hash = :hash ORDER BY c.ord;
