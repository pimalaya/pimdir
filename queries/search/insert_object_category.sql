-- One of a card's CATEGORIES values (§6), folded, written with the object; a
-- value the card states twice is one row. The rows go by cascade when the
-- object row does.
INSERT OR IGNORE INTO object_category(object, value) VALUES(:object, :value);
