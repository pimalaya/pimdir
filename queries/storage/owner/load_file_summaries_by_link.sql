-- The file summaries, on load_mail_summaries_by_link's terms.
SELECT i.link_id, s.name, s.media_type, s.size, s.part
FROM items i JOIN file_summary s ON s.item = i.id WHERE i.collection = :collection
  AND i.link_id IN (SELECT value FROM temp.param WHERE slot = 'links');
