-- The contact summaries, on load_mail_summaries_by_link's terms.
SELECT i.link_id, s.uid, s.fn, s.kind, s.org
FROM items i JOIN contact_summary s ON s.item = i.id WHERE i.collection = :collection
  AND i.link_id IN (SELECT value FROM temp.param WHERE slot = 'links');
