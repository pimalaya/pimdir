-- The categories of the tasks in the `links` slot, on
-- load_in_reply_to_by_link's terms (Annex A.4).
SELECT i.link_id, c.position, c.value
FROM items i JOIN task_category c ON c.item = i.id
WHERE i.collection = :collection
  AND i.link_id IN (SELECT value FROM temp.param WHERE slot = 'links')
ORDER BY i.link_id, c.position;
