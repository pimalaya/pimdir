-- The contact summaries, on load_mail_summaries's terms.
SELECT i.link_id, s.uid, s.fn, s.kind, s.org
FROM items i JOIN contact_summary s ON s.item = i.id WHERE i.collection = :collection;
