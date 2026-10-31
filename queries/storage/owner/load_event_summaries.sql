-- The event summaries, on load_mail_summaries's terms.
SELECT link_id, uid, summary, location, dtstart, dtstart_tzid, dtstart_value, dtend, recurring, until
FROM event_summary WHERE collection = :collection;
