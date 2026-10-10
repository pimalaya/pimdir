INSERT INTO file_summary(collection, link_id, name, media_type, size, part)
VALUES(:collection, :link_id, :name, :media_type, :size, :part)
ON CONFLICT(collection, link_id) DO UPDATE SET
    name = excluded.name, media_type = excluded.media_type, size = excluded.size,
    part = excluded.part;
