INSERT INTO mail_summary(collection, link_id, message_id, in_reply_to, subject,
                         sender, sender_name, date, size, attachment)
VALUES(:collection, :link_id, :message_id, :in_reply_to, :subject,
       :sender, :sender_name, :date, :size, :attachment)
ON CONFLICT(collection, link_id) DO UPDATE SET
    message_id = excluded.message_id, in_reply_to = excluded.in_reply_to,
    subject = excluded.subject, sender = excluded.sender,
    sender_name = excluded.sender_name, date = excluded.date,
    size = excluded.size, attachment = excluded.attachment;
