-- The categories of a collection's tasks, on load_in_reply_to's terms
-- (Annex A.4).
SELECT link_id, position, value FROM task_category
WHERE collection = :collection
  AND (:scoped = 0 OR link_id IN (SELECT value FROM temp.param WHERE slot = 'links'))
ORDER BY link_id, position;
