-- A renamed collection counts as moved.
SELECT id, account, kind, name, changed FROM collections
WHERE changed > :since ORDER BY changed LIMIT :limit;
