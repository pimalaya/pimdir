-- The contact summaries, on load_mail_summaries's terms.
SELECT link_id, uid, fn, kind, org
FROM contact_summary WHERE collection = :collection;
