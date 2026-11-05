-- A reference's endpoint (§14.2) as a link shows it: its first live
-- placement under the kind, by collection id, and a title from whichever
-- summary it has: a subject, a name, a summary, a file's name. No row when no
-- live placement holds it.
SELECT i.collection, i.seq,
       coalesce(ms.subject, cs.fn, es.summary, ts.summary, js.summary, fs.name) AS title
FROM items i
JOIN collections c ON c.id = i.collection AND c.kind = :kind
LEFT JOIN mail_summary ms ON ms.item = i.id
LEFT JOIN contact_summary cs ON cs.item = i.id
LEFT JOIN event_summary es ON es.item = i.id
LEFT JOIN task_summary ts ON ts.item = i.id
LEFT JOIN journal_summary js ON js.item = i.id
LEFT JOIN file_summary fs ON fs.item = i.id
WHERE i.link_id = :link_id AND i.deleted = 0
ORDER BY i.collection LIMIT 1;
