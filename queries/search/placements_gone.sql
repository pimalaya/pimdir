-- Placements the index holds and the store no longer does: purged rows, or a
-- renamed collection's old id. Run when store_meta.purges or a collection
-- stamp moved.
SELECT p.collection, p.seq FROM placement p
LEFT JOIN store.items i ON i.collection = p.collection AND i.seq = p.seq
WHERE i.seq IS NULL;
