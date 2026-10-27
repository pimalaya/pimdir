-- The source rule from the other end (§14.2): the references link_sources_of
-- records, for the tasks naming one mail, so a mail synced after the task it
-- became is still tied to it. :link_id names the mail, NULL every one, on
-- link_senders_of's range; task_summary_by_mid finds the tasks.
INSERT INTO item_reference(from_kind, from_link_id, to_kind, to_link_id, role, origin, created_at)
SELECT DISTINCT 'text/calendar', ti.link_id, 'message/rfc822', mi.link_id, 'source', 'auto',
       strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
FROM items mi
JOIN collections mc ON mc.id = mi.collection AND mc.kind = 'message/rfc822'
JOIN task_summary t ON t.mid = mi.link_id
JOIN items ti ON ti.collection = t.collection AND ti.link_id = t.link_id AND ti.deleted = 0
WHERE mi.link_id BETWEEN coalesce(:link_id, '') AND coalesce(:link_id, x'') AND mi.deleted = 0
  AND NOT (ti.link_id GLOB 'alt:*' OR ti.link_id GLOB 'dup:*' OR ti.link_id GLOB 'hash:*') AND NOT (mi.link_id GLOB 'alt:*' OR mi.link_id GLOB 'dup:*' OR mi.link_id GLOB 'hash:*')
ON CONFLICT DO NOTHING;
