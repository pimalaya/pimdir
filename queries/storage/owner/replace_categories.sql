-- A task's categories (Annex A.4), on replace_in_reply_to's terms, followed by
-- one insert_category per value.
DELETE FROM task_category WHERE collection = :collection AND link_id = :link_id;
