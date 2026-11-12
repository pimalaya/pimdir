INSERT INTO mail_in_reply_to(item, position, message_id)
VALUES((SELECT id FROM items WHERE collection = :collection AND link_id = :link_id), :position, :message_id);
