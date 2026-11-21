-- The live placements whose item holds one value under a key (§4.3), the
-- value compared byte for byte, each once, by collection and public id:
-- property: and each spelling label: reads (SEARCH.md §8). A seek on
-- item_property_by_value, then each seq on items_by_seq_global.
SELECT i.collection, i.seq
FROM item_property p JOIN items i ON i.seq = p.seq
WHERE p.key = :key AND p.value = :value AND i.deleted = 0
ORDER BY i.collection, i.seq;
