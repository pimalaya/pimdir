-- The parent rule from the other end (§14.2): the references link_parents_of
-- records, for the tasks naming one calendar item their parent, so a parent
-- synced after its children is still tied to them. :link_id names the
-- calendar item, NULL every one, on link_senders_of's range;
-- task_summary_by_parent finds the tasks.
INSERT INTO item_reference(from_kind, from_link_id, to_kind, to_link_id, role, origin, created_at)
SELECT DISTINCT 'text/calendar', ti.link_id, 'text/calendar', p.link_id, 'parent', 'auto',
       strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
FROM items p
JOIN collections pc ON pc.id = p.collection AND pc.kind = 'text/calendar'
JOIN task_summary t ON t.parent = p.link_id
JOIN items ti ON ti.collection = t.collection AND ti.link_id = t.link_id AND ti.deleted = 0
WHERE p.link_id BETWEEN coalesce(:link_id, '') AND coalesce(:link_id, x'') AND p.deleted = 0
  AND p.link_id != ti.link_id
  AND NOT (ti.link_id GLOB 'alt:*' OR ti.link_id GLOB 'dup:*' OR ti.link_id GLOB 'hash:*') AND NOT (p.link_id GLOB 'alt:*' OR p.link_id GLOB 'dup:*' OR p.link_id GLOB 'hash:*')
ON CONFLICT DO NOTHING;
