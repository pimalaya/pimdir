-- Which of the message ids the `ids` slot names (bare ids, as Annex A.1
-- stores mail_in_reply_to and A.4 a task's mid) some live mail replies to, its
-- mail_in_reply_to naming the id: the mail a task came from answered. Mail
-- filed under the sent or drafts role is the person's own and answers nothing.
-- Each id answered once, in code point order. A seek per id on
-- mail_in_reply_to_by_id.
SELECT DISTINCT r.msg_id
FROM mail_in_reply_to r
JOIN items i ON i.collection = r.collection AND i.link_id = r.link_id
JOIN collections c ON c.id = r.collection
WHERE i.deleted = 0
  AND (c.role IS NULL OR c.role NOT IN ('sent', 'drafts'))
  AND r.msg_id IN (SELECT value FROM temp.param WHERE slot = 'ids')
ORDER BY r.msg_id;
