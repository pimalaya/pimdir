-- The event summaries, on load_mail_summaries's terms.
SELECT i.link_id, s.uid, s.summary, s.location, s.dtstart, s.dtstart_tzid, s.dtstart_value, s.dtend, s.recurring, s.until
FROM items i JOIN event_summary s ON s.item = i.id WHERE i.collection = :collection;
