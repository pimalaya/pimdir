-- Replaced as a set, as replace_addresses replaces the addresses: the
-- derivation yields the whole list (Annex A.1). Followed by one
-- insert_in_reply_to per id, and by stamp_item when nothing else about the
-- item moved (§4.5).
DELETE FROM mail_in_reply_to WHERE collection = :collection AND link_id = :link_id;
