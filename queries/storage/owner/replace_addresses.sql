-- Replaced as a set: the derivation yields the whole list, and a diff buys
-- nothing on a handful of rows. Followed by stamp_item when nothing else
-- about the item moved (§4.5).
DELETE FROM item_address WHERE collection = :collection AND link_id = :link_id;
