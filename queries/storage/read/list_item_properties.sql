-- An item's properties (§4.3): every key and value its public id holds, in
-- key then value order, byte for byte. They are the item's whatever the state
-- of a row holding the seq, so a trash view reads them too. A seek on the
-- table's key.
SELECT key, value FROM item_property WHERE seq = :seq ORDER BY key, value;
