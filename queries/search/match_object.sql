-- Whether one body matches a text term (§8.2): a probe by rowid into the
-- term's matches, for a client walking the store's order. One row when it
-- matches, none otherwise. :match is compiled as §8.5 says.
SELECT 1 AS matched FROM object_text
WHERE object_text MATCH :match AND rowid = (SELECT id FROM object WHERE hash = :hash);
