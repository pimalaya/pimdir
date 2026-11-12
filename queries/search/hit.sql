-- One hit's presentation rows (§8.2), joined out of the store: every live
-- placement of the hit `(account, seq)`, :account NULL for the collections
-- of no account, in collection order, each with its row as a listing reads
-- it, its collection's kind, the `kind:` value it answers to (§8; NULL for a
-- calendar item holding no summary row) and its title, '' when it has none.
-- A tombstone and a retained row are no placement of a hit. A hit names no
-- collection, so the read seeks the public id on items_by_seq_global.
SELECT i.collection, i.link_id,
       CASE WHEN i.flags_known = 1
            THEN trim(CASE WHEN i.marks & 1 THEN '\Seen ' ELSE '' END
                   || CASE WHEN i.marks & 2 THEN '\Answered ' ELSE '' END
                   || CASE WHEN i.marks & 4 THEN '\Flagged ' ELSE '' END
                   || CASE WHEN i.marks & 8 THEN '\Draft ' ELSE '' END
                   || CASE WHEN i.marks & 16 THEN '\Deleted ' ELSE '' END
                   || coalesce((SELECT group_concat(g.flag, ' ') FROM store.placement_flag g WHERE g.item = i.id), '')) END AS flags,
       i.object_hash, i.sort_key, i.level, c.kind,
       CASE c.kind
         WHEN 'message/rfc822' THEN 'mail'
         WHEN 'text/vcard' THEN 'contact'
         WHEN 'application/octet-stream' THEN 'file'
         WHEN 'text/calendar' THEN CASE
           WHEN e.item IS NOT NULL THEN 'event'
           WHEN t.item IS NOT NULL THEN 'task'
           WHEN j.item IS NOT NULL THEN 'journal'
         END
       END AS kind_value,
       coalesce(m.subject, k.fn, e.summary, t.summary, j.summary, f.name, '') AS title
FROM store.items i
JOIN store.collections c ON c.id = i.collection
LEFT JOIN store.mail_summary m ON m.item = i.id
LEFT JOIN store.contact_summary k ON k.item = i.id
LEFT JOIN store.event_summary e ON e.item = i.id
LEFT JOIN store.task_summary t ON t.item = i.id
LEFT JOIN store.journal_summary j ON j.item = i.id
LEFT JOIN store.file_summary f ON f.item = i.id
WHERE i.seq = :seq AND c.account IS :account AND i.deleted = 0 AND i.retained_at IS NULL
ORDER BY i.collection;
