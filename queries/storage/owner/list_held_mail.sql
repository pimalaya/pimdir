-- The mail rows holding a body, store-wide, live or not, for the
-- re-derivation of a later Annex A revision (§6): a keyset page on the key
-- (collection, link_id), a NULL :after_collection the first page, coalesced
-- to the empty text, below every key, a link id never being empty (§9), so
-- the cursor stays the seek on the key at any depth.
SELECT i.collection, i.link_id, i.seq, i.object_hash
FROM items i JOIN collections c ON c.id = i.collection AND c.kind = 'message/rfc822'
WHERE i.object_hash IS NOT NULL
  AND (i.collection, i.link_id) > (coalesce(:after_collection, ''), coalesce(:after_link_id, ''))
ORDER BY i.collection, i.link_id LIMIT :limit;
