-- Narrowed to the link ids one write batch touches. Reading the rest costs a
-- full pass over the collection to compute nothing, and that cost grows with
-- the mailbox rather than with the batch (§14).
SELECT link_id,
       CASE WHEN items.flags_known = 1
            THEN coalesce((SELECT group_concat(f.flag, ' ') FROM placement_flag f
                           WHERE f.collection = items.collection AND f.link_id = items.link_id), '') END AS flags,
       object_hash, sort_key, level, deleted, conflicted, conflict_object
FROM items WHERE collection = :collection AND retained_at IS NULL
  AND link_id IN (SELECT value FROM temp.param WHERE slot = 'links');
