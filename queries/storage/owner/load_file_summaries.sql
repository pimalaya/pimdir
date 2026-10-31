-- The file summaries, on load_mail_summaries's terms.
SELECT link_id, name, media_type, size, part
FROM file_summary WHERE collection = :collection
  AND (:scoped = 0 OR link_id IN (SELECT value FROM temp.param WHERE slot = 'links'));
