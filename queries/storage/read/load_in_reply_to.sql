-- The In-Reply-To ids of a collection's mail, in document order: what a mail
-- row carries beside its summary (Annex A.1), on load_addresses_by_collection's
-- terms. load_in_reply_to_by_link reads those of a page's link ids.
SELECT i.link_id, r.position, r.msg_id
FROM items i JOIN mail_in_reply_to r ON r.item = i.id
WHERE i.collection = :collection
ORDER BY i.link_id, r.position;
