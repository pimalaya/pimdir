-- Whether one bodiless placement's summary matches a text term (§8.2), as
-- match_object probes a body. :match is compiled as §8.5 says.
SELECT 1 AS matched FROM summary_text
WHERE summary_text MATCH :match
  AND rowid = (SELECT id FROM placement WHERE collection = :collection AND seq = :seq);
