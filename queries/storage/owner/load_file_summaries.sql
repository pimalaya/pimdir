-- The file summaries, on load_mail_summaries's terms.
SELECT link_id, name, media_type, size, part
FROM file_summary WHERE collection = :collection;
