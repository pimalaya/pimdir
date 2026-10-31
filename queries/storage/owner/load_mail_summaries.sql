-- The mail summaries of a collection, or with :scoped 1 of the link ids in
-- the `links` slot, so the diff upserts a row only when it moved (§4.5). The
-- In-Reply-To ids are load_in_reply_to's.
SELECT link_id, message_id, subject, sender, sender_name, date, size, attachment,
       invitation
FROM mail_summary WHERE collection = :collection
  AND (:scoped = 0 OR link_id IN (SELECT value FROM temp.param WHERE slot = 'links'));
