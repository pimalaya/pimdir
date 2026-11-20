-- Where a collection sits in its account's hierarchy, as its source states
-- it (an IMAP or JMAP parent, the DAV collection containing it), or NULL at
-- the top. The parent is a collection of the same account, never the
-- collection itself nor one under it, so the hierarchy stays a forest within
-- an account: a parent outside that, or unknown, leaves the row as it was,
-- and the owner reads the change count, none for a refusal. A parent renamed
-- or deleted is followed by its foreign key.
UPDATE collections SET parent = :parent
WHERE id = :collection
  AND (:parent IS NULL OR EXISTS (
      SELECT 1 FROM collections p, collections c
      WHERE p.id = :parent AND c.id = :collection AND p.account IS c.account))
  AND (:parent IS NULL OR NOT EXISTS (
      WITH RECURSIVE above(id) AS (
          SELECT :parent
          UNION
          SELECT collections.parent FROM collections JOIN above ON collections.id = above.id
          WHERE collections.parent IS NOT NULL)
      SELECT 1 FROM above WHERE above.id = :collection));
