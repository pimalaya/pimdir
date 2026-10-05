-- What the source says a collection is for, or NULL when it no longer says.
-- Only from what a source states, never guessed from a name. A role another
-- collection of the account and the kind holds leaves it in this statement
-- (the collections_role_moves trigger), so the move is one write. The
-- collection is declared first: a role outside its kind's vocabulary, or on
-- an undeclared kind, is refused.
UPDATE collections SET role = :role WHERE id = :collection;
