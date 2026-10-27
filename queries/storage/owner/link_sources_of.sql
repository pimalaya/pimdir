-- The source rule (§14.2): a reference from a task to the mail its mid names
-- by link id, role `source`, origin `auto`, both ends live. :link_id names
-- the task, NULL every task, on link_senders_of's range. A reference already
-- recorded is left as it is.
INSERT INTO item_reference(from_kind, from_link_id, to_kind, to_link_id, role, origin, created_at)
SELECT DISTINCT 'text/calendar', ti.link_id, 'message/rfc822', mi.link_id, 'source', 'auto',
       strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
FROM items ti
JOIN task_summary t ON t.collection = ti.collection AND t.link_id = ti.link_id
JOIN items mi ON mi.link_id = t.mid AND mi.deleted = 0
JOIN collections mc ON mc.id = mi.collection AND mc.kind = 'message/rfc822'
WHERE ti.link_id BETWEEN coalesce(:link_id, '') AND coalesce(:link_id, x'') AND ti.deleted = 0
  AND NOT (ti.link_id GLOB 'alt:*' OR ti.link_id GLOB 'dup:*' OR ti.link_id GLOB 'hash:*') AND NOT (mi.link_id GLOB 'alt:*' OR mi.link_id GLOB 'dup:*' OR mi.link_id GLOB 'hash:*')
ON CONFLICT DO NOTHING;
