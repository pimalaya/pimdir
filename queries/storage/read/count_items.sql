SELECT count(*) AS count FROM items WHERE collection = :collection AND deleted = 0;
