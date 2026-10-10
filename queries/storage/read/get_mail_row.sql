-- One live mail row by collection and link id, in list_mail_page_filtered's
-- column shape, so a reader holding a key reads its row without a page.
SELECT i.collection, i.seq, i.link_id, i.flags, i.object_hash, i.sort_key, i.level,
       s.message_id, s.in_reply_to, s.subject, s.sender, s.sender_name, s.date, s.size, s.attachment
FROM items i LEFT JOIN mail_summary s ON s.collection = i.collection AND s.link_id = i.link_id
WHERE i.collection = :collection AND i.link_id = :link_id AND i.deleted = 0;
