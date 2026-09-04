-- Narrowed to the link ids one write batch touches. Reading the rest costs a
-- full pass over the collection to compute nothing, and that cost grows with
-- the mailbox rather than with the batch (§14).
SELECT link_id, flags, object_hash, sort_key, level, deleted, conflicted, conflict_object
FROM items WHERE collection = :collection AND retained_at IS NULL
  AND link_id IN (SELECT value FROM json_each(:links));
