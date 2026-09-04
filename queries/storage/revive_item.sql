-- A link id that reappears revives the retained row holding its primary key
-- instead of conflicting on it, keeping its seq, so a restored item never gets
-- a second public id (§9.1). The caller adopts the new content in the same
-- transaction.
UPDATE items SET deleted = 0, retained_at = NULL, retained_by = NULL
WHERE collection = :collection AND link_id = :link_id;
