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
FROM bindings b JOIN items i ON i.id = b.item WHERE b.collection = :collection;
