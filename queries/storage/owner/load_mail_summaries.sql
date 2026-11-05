-- The mail summaries of a collection, so a diff over all of it upserts a row
-- only when it moved (§4.5); load_mail_summaries_by_link reads a batch's. The
-- In-Reply-To ids are load_in_reply_to's.
SELECT i.link_id, s.message_id, s.subject, s.sender, s.sender_name, s.date, s.size, s.attachment,
       s.invitation
FROM items i JOIN mail_summary s ON s.item = i.id WHERE i.collection = :collection;
