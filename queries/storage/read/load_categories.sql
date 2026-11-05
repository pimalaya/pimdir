-- The categories of a collection's tasks, on load_in_reply_to's terms
-- (Annex A.4).
SELECT i.link_id, c.position, c.value
FROM items i JOIN task_category c ON c.item = i.id
WHERE i.collection = :collection
ORDER BY i.link_id, c.position;
