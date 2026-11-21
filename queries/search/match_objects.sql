-- Every placement whose body matches, ranked. :match is a text term compiled
-- as §8.5 says, never the user's text. A match's rowid is its body's
-- object.id, which placement_by_object seeks.
SELECT p.collection, p.seq, bm25(object_text) AS rank
FROM object_text
JOIN placement p ON p.object = object_text.rowid
WHERE object_text MATCH :match;
