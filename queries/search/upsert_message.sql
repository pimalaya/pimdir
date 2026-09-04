INSERT INTO message(link_id, thread, parent) VALUES(:link_id, :thread, :parent)
ON CONFLICT(link_id) DO UPDATE SET thread = excluded.thread, parent = excluded.parent;
