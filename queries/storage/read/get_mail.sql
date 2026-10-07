-- A LEFT JOIN: an item with no summary row (Annex A.3) still lists.
SELECT i.seq, i.link_id, i.flags, i.object_hash, i.sort_key, i.level,
       s.message_id, s.in_reply_to, s.subject, s.sender, s.sender_name, s.date, s.size, s.attachment
FROM items i LEFT JOIN mail_summary s ON s.collection = i.collection AND s.link_id = i.link_id
WHERE i.collection = :collection AND i.seq = :seq AND i.deleted = 0;
