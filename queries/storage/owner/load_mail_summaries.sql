-- The mail summaries of a collection, or of the link ids in :links (a JSON
-- array) when bound, so the diff upserts a row only when it moved (§4.5).
SELECT link_id, message_id, in_reply_to, subject, sender, sender_name, date, size, attachment
FROM mail_summary WHERE collection = :collection
  AND (:links IS NULL OR link_id IN (SELECT value FROM json_each(:links)));
