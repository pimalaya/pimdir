-- Narrowed to the link ids one write batch touches: the binding half of
-- load_items_by_link.
SELECT link_id, source, handle,
       CASE WHEN b.base_flags_known = 1
            THEN coalesce((SELECT group_concat(g.flag, ' ') FROM binding_base_flag g
                           WHERE g.collection = b.collection AND g.link_id = b.link_id
                             AND g.source = b.source), '') END AS base_flags,
       base_object, base_revision, base_present, conflicted, conflict_revision,
       conflict_object, shared_object
FROM bindings b WHERE collection = :collection
  AND link_id IN (SELECT value FROM temp.param WHERE slot = 'links');
