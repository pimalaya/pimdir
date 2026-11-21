-- The live placements whose item holds a key (§4.3), whatever its values,
-- each once, by collection and public id: every item an application
-- snoozed. The key's rows are read on item_property_by_value, then each seq
-- on items_by_seq_global, so the read costs what holds the key.
SELECT i.collection, i.seq FROM items i
WHERE i.seq IN (SELECT p.seq FROM item_property p WHERE p.key = :key)
  AND i.deleted = 0
ORDER BY i.collection, i.seq;
