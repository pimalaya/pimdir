-- Every placement whose body matches, ranked. :match is the compiled FTS5
-- expression, never the user's text (§8).
SELECT p.collection, p.seq, bm25(object_text) AS rank
FROM object_text
JOIN object o ON o.id = object_text.rowid
JOIN placement p ON p.hash = o.hash
WHERE object_text MATCH :match;
