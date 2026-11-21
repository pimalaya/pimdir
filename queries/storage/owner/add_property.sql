-- Adds one value under a key to the properties of the item a seq names
-- (§15.3), a value the key holds already changing nothing and stamping
-- nothing. The schema refuses a seq no row holds, a key or a value past its
-- bounds and a 65th value under one key (§13), and stamps every row holding
-- the seq (§4.5). A label compared folded is the caller's, which reads the
-- values held first (list_item_properties), since SQLite folds no Unicode.
INSERT INTO item_property(seq, key, value) VALUES(:seq, :key, :value)
ON CONFLICT DO NOTHING;
