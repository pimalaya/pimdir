-- Placements the index holds and the store no longer does: purged rows, or a
-- renamed collection's old id. Run when store_meta.purges moved, which a
-- purge, a collection and a rename all count in (§4); the link id names the
-- message whose thread is pruned when it was the last placement (§9).
SELECT p.collection, p.seq, p.link_id FROM placement p
LEFT JOIN store.items i ON i.collection = p.collection AND i.seq = p.seq
WHERE i.seq IS NULL;
