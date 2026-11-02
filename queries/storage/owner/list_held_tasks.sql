-- The task rows holding a body, store-wide, live or not, for the
-- re-derivation of a later Annex A revision (§6): a keyset page on the key
-- (collection, link_id), on list_held_mail's terms.
SELECT i.collection, i.link_id, i.seq, i.object_hash
FROM task_summary t JOIN items i ON i.collection = t.collection AND i.link_id = t.link_id
WHERE i.object_hash IS NOT NULL
  AND (t.collection, t.link_id) > (coalesce(:after_collection, ''), coalesce(:after_link_id, ''))
ORDER BY t.collection, t.link_id LIMIT :limit;
