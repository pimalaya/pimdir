-- Writes the four columns re-derived from one held task body (Annex A.4),
-- priority, categories, parent and mid, into a row written before they
-- existed, during reconciliation's backfill (§6), a page of list_held_tasks at
-- a time. `categories` is the JSON array Annex A.4 writes.
UPDATE task_summary SET priority = :priority, categories = :categories, parent = :parent, mid = :mid
WHERE collection = :collection AND link_id = :link_id;
