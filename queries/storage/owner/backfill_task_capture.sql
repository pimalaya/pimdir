-- Writes when a task was captured, re-derived from one held task body
-- (Annex A.4, revision 2), into a row derived before the column existed:
-- the re-derivation of §6, a page of list_held_tasks at a time.
UPDATE task_summary SET created = :created
WHERE collection = :collection AND link_id = :link_id;
