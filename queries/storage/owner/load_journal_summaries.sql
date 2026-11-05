-- The journal summaries, on load_mail_summaries's terms.
SELECT i.link_id, s.uid, s.summary, s.dtstart, s.dtstart_tzid, s.dtstart_value
FROM items i JOIN journal_summary s ON s.item = i.id WHERE i.collection = :collection;
