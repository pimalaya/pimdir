DELETE FROM placement WHERE collection = :collection AND seq = :seq RETURNING rowid;
