INSERT INTO file_summary(item, name, media_type, size, part)
VALUES((SELECT id FROM items WHERE collection = :collection AND link_id = :link_id), :name, :media_type, :size, :part)
ON CONFLICT(item) DO UPDATE SET
    name = excluded.name, media_type = excluded.media_type, size = excluded.size,
    part = excluded.part;
