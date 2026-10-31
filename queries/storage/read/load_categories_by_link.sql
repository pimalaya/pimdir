-- The categories of the tasks in the `links` slot, on
-- load_in_reply_to_by_link's terms (Annex A.4).
SELECT link_id, position, value FROM task_category
WHERE collection = :collection
  AND link_id IN (SELECT value FROM temp.param WHERE slot = 'links')
ORDER BY link_id, position;
