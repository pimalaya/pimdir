-- One chunk of a body's `body` or `note` field (§6), written with the object;
-- the rows go by cascade when the object row does.
INSERT INTO chunk(object, ord, field, start, end) VALUES(:object, :ord, :field, :start, :end);
