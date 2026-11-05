INSERT INTO mail_in_reply_to(item, position, msg_id)
VALUES((SELECT id FROM items WHERE collection = :collection AND link_id = :link_id), :position, :msg_id);
