-- The file summaries, on load_mail_summaries_by_link's terms.
SELECT link_id, name, media_type, size, part
FROM file_summary WHERE collection = :collection
  AND link_id IN (SELECT value FROM temp.param WHERE slot = 'links');
