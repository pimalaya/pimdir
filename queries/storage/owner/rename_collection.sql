-- The only safe way to change an id, and where both a server-side rename and an
-- account rename that renamespaced it land (§9.2). Every foreign key onto
-- collections(id) is ON UPDATE CASCADE, so items, sources, bindings, queue rows
-- and children follow in one statement; deleting and recreating instead
-- cascades the delete, turning a rename into a full re-download (§14).
UPDATE collections SET id = :new_id WHERE id = :collection;
