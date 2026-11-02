-- The mail summaries of the link ids in the `links` slot, a seek per id: what
-- the diff of one write batch reads (§14), however large the collection. The
-- In-Reply-To ids are load_in_reply_to_by_link's.
SELECT link_id, message_id, subject, sender, sender_name, date, size, attachment,
       invitation
FROM mail_summary WHERE collection = :collection
  AND link_id IN (SELECT value FROM temp.param WHERE slot = 'links');
