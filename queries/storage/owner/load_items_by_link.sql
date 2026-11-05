-- Narrowed to the link ids one write batch touches. Reading the rest costs a
-- full pass over the collection to compute nothing, and that cost grows with
-- the mailbox rather than with the batch (§14).
SELECT link_id,
       CASE WHEN items.flags_known = 1
            THEN trim(CASE WHEN items.marks & 1 THEN '\Seen ' ELSE '' END
                   || CASE WHEN items.marks & 2 THEN '\Answered ' ELSE '' END
                   || CASE WHEN items.marks & 4 THEN '\Flagged ' ELSE '' END
                   || CASE WHEN items.marks & 8 THEN '\Draft ' ELSE '' END
                   || CASE WHEN items.marks & 16 THEN '\Deleted ' ELSE '' END
                   || coalesce((SELECT group_concat(f.flag, ' ') FROM placement_flag f WHERE f.item = items.id), '')) END AS flags,
       object_hash, sort_key, level, deleted, conflicted, conflict_object
FROM items WHERE collection = :collection AND retained_at IS NULL
  AND link_id IN (SELECT value FROM temp.param WHERE slot = 'links');
