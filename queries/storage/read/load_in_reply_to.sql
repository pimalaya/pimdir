-- The In-Reply-To ids of a collection's mail, in document order: what a mail
-- row carries beside its summary (Annex A.1), on load_addresses_by_collection's
-- terms. load_in_reply_to_by_link reads those of a page's link ids.
SELECT link_id, position, msg_id FROM mail_in_reply_to
WHERE collection = :collection
ORDER BY link_id, position;
