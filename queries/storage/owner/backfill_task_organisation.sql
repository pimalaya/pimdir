-- Writes the three columns re-derived from one held task body (Annex A.4),
-- priority, parent and mid, into a row written before they existed, during
-- reconciliation's backfill (§6), a page of list_held_tasks at a time, its
-- categories written beside it with replace_categories and insert_category.
UPDATE task_summary SET priority = :priority, parent = :parent, mid = :mid
WHERE collection = :collection AND link_id = :link_id;
