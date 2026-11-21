-- Removes one value under a key from the properties of the item a seq names
-- (§15.3), compared byte for byte, a value not held changing nothing; a
-- removal stamps every row holding the seq (§4.5).
DELETE FROM item_property WHERE seq = :seq AND key = :key AND value = :value;
