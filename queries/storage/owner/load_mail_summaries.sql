-- The mail summaries of a collection, so a diff over all of it upserts a row
-- only when it moved (§4.5); load_mail_summaries_by_link reads a batch's. The
-- In-Reply-To ids are load_in_reply_to's.
SELECT link_id, message_id, subject, sender, sender_name, date, size, attachment,
       invitation
FROM mail_summary WHERE collection = :collection;
