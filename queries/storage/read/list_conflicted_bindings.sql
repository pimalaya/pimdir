-- The bindings waiting for a decision, across one account's collections: what
-- each one is, and the three bodies a resolver merges. The base is what the two
-- sides last agreed on, the item's own object_hash is the local side, and
-- conflict_object is the remote one at conflict_revision, so a resolver holding
-- no credentials reads the whole divergence from the store (§13).
-- Rides bindings_conflicted, which holds only the outstanding rows: a run
-- reports this count on every invocation, and answering it by paging each
-- collection costs a pass over the whole store for a number usually zero.
SELECT b.collection, b.link_id, b.source, b.handle, b.conflict_revision,
       b.base_object, i.object_hash, b.conflict_object
FROM bindings b
JOIN items i ON i.collection = b.collection AND i.link_id = b.link_id
JOIN collections c ON c.id = b.collection
WHERE b.conflicted = 1 AND c.account IS :account
ORDER BY b.collection, b.link_id, b.source;
