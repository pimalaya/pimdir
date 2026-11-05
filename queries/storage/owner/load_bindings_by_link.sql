-- Narrowed to the link ids one write batch touches: the binding half of
-- load_items_by_link.
SELECT i.link_id, b.source, b.handle,
       CASE WHEN b.base_flags_known = 1
            THEN trim(CASE WHEN b.base_marks & 1 THEN '\Seen ' ELSE '' END
                   || CASE WHEN b.base_marks & 2 THEN '\Answered ' ELSE '' END
                   || CASE WHEN b.base_marks & 4 THEN '\Flagged ' ELSE '' END
                   || CASE WHEN b.base_marks & 8 THEN '\Draft ' ELSE '' END
                   || CASE WHEN b.base_marks & 16 THEN '\Deleted ' ELSE '' END
                   || coalesce((SELECT group_concat(g.flag, ' ') FROM binding_base_flag g WHERE g.item = b.item AND g.source = b.source), '')) END AS base_flags,
       b.base_object, b.base_revision, b.base_present, b.conflicted, b.conflict_revision,
       b.conflict_object, b.shared_object
FROM items i JOIN bindings b ON b.item = i.id WHERE i.collection = :collection
  AND i.link_id IN (SELECT value FROM temp.param WHERE slot = 'links');
