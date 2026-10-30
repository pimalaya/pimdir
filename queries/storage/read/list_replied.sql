-- Which of the message ids :ids names (a JSON array of bare ids, as Annex A.1
-- stores in_reply_to and A.4 a task's mid) some live mail replies to, its
-- in_reply_to naming the id: the mail a task came from answered. Mail
-- filed under the sent or drafts role is the person's own and answers nothing.
-- Each id answered once, in code point order. A scan of mail_summary, no index
-- reading into a JSON array; the search part's thread tables answer it by seek.
SELECT DISTINCT j.value
FROM mail_summary m
JOIN json_each(m.in_reply_to) j
JOIN items i ON i.collection = m.collection AND i.link_id = m.link_id
JOIN collections c ON c.id = m.collection
WHERE i.deleted = 0
  AND (c.role IS NULL OR c.role NOT IN ('sent', 'drafts'))
  AND j.value IN (SELECT value FROM json_each(:ids))
ORDER BY j.value;
