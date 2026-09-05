-- Takes the placement's flags and occurrences by cascade; the caller deletes
-- its summary text by the returned rowid (§4).
DELETE FROM placement WHERE collection = :collection AND seq = :seq RETURNING id;
