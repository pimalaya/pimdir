-- The refusals standing in one collection (§14.1, SYNC.md §5), per item and
-- source: the item's seq, the handle the change was refused under, the reason,
-- the key of the change refused and when. A frontend lists them beside its
-- queue; an engine loads its source's, holding a change whose key one names.
-- Seeks bindings_refused, which holds the refused bindings alone.
SELECT i.seq, b.source, b.handle, b.refusal, b.refused_key, b.refused_at
FROM bindings b JOIN items i ON i.id = b.item
WHERE b.collection = :collection AND b.refusal IS NOT NULL
ORDER BY i.seq, b.source;
