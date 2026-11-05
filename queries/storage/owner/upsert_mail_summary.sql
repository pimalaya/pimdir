-- An unknown invitation (NULL) never clears a known one: the message is
-- immutable, so what its body once said it still says (Annex A.1).
INSERT INTO mail_summary(item, message_id, subject,
                         sender, sender_name, date, size, attachment, invitation)
VALUES((SELECT id FROM items WHERE collection = :collection AND link_id = :link_id), :message_id, :subject,
       :sender, :sender_name, :date, :size, :attachment, :invitation)
ON CONFLICT(item) DO UPDATE SET
    message_id = excluded.message_id,
    subject = excluded.subject, sender = excluded.sender,
    sender_name = excluded.sender_name, date = excluded.date,
    size = excluded.size, attachment = excluded.attachment,
    invitation = coalesce(excluded.invitation, invitation);
