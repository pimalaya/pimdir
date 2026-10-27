-- The parent rule (§14.2): a reference from a task to the calendar item its
-- parent names by link id, role `parent`, origin `auto`, both ends live.
-- :link_id names the task, NULL every task, on link_senders_of's range. A
-- reference already recorded is left as it is.
INSERT INTO item_reference(from_kind, from_link_id, to_kind, to_link_id, role, origin, created_at)
SELECT DISTINCT 'text/calendar', ti.link_id, 'text/calendar', p.link_id, 'parent', 'auto',
       strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
FROM items ti
JOIN task_summary t ON t.collection = ti.collection AND t.link_id = ti.link_id
JOIN items p ON p.link_id = t.parent AND p.deleted = 0
JOIN collections pc ON pc.id = p.collection AND pc.kind = 'text/calendar'
WHERE ti.link_id BETWEEN coalesce(:link_id, '') AND coalesce(:link_id, x'') AND ti.deleted = 0
  AND p.link_id != ti.link_id
  AND NOT (ti.link_id GLOB 'alt:*' OR ti.link_id GLOB 'dup:*' OR ti.link_id GLOB 'hash:*') AND NOT (p.link_id GLOB 'alt:*' OR p.link_id GLOB 'dup:*' OR p.link_id GLOB 'hash:*')
ON CONFLICT DO NOTHING;
