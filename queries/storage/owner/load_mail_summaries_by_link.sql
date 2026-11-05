-- The mail summaries of the link ids in the `links` slot, a seek per id: what
-- the diff of one write batch reads (§14), however large the collection. The
-- In-Reply-To ids are load_in_reply_to_by_link's.
SELECT i.link_id, s.message_id, s.subject, s.sender, s.sender_name, s.date, s.size, s.attachment,
       s.invitation
FROM items i JOIN mail_summary s ON s.item = i.id WHERE i.collection = :collection
  AND i.link_id IN (SELECT value FROM temp.param WHERE slot = 'links');
