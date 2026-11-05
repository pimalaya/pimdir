-- The journal summaries, on load_mail_summaries_by_link's terms.
SELECT i.link_id, s.uid, s.summary, s.dtstart, s.dtstart_tzid, s.dtstart_value
FROM items i JOIN journal_summary s ON s.item = i.id WHERE i.collection = :collection
  AND i.link_id IN (SELECT value FROM temp.param WHERE slot = 'links');
