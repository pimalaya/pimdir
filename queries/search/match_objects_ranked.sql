-- The placements of the bodies a text term matches best (§8.2), a page of
-- :limit bodies after the first :offset, best first: FTS5 orders by its rank
-- and keeps the page, so no row past it reaches the joins or the client.
-- :match is compiled as §8.5 says.
SELECT p.collection, p.seq, m.rank
FROM (SELECT rowid, rank FROM object_text WHERE object_text MATCH :match
      ORDER BY rank LIMIT :limit OFFSET :offset) m
JOIN object o ON o.id = m.rowid
JOIN placement p ON p.hash = o.hash
ORDER BY m.rank, p.seq, p.collection;
