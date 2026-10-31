-- The contact summaries, on load_mail_summaries's terms.
SELECT link_id, uid, fn, kind, org
FROM contact_summary WHERE collection = :collection
  AND (:scoped = 0 OR link_id IN (SELECT value FROM temp.param WHERE slot = 'links'));
