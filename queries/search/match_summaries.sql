SELECT p.collection, p.seq, bm25(summary_text) AS rank
FROM summary_text
JOIN placement p ON p.id = summary_text.rowid
WHERE summary_text MATCH :match;
