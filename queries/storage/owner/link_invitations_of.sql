-- The invitation rule (§14.2): a reference from a mail to the calendar item
-- its `invitation` names by link id, role `invitation`, origin `auto`, both
-- ends live. :link_id names the mail, NULL every mail, on link_senders_of's
-- range. A reference already recorded is left as it is.
INSERT INTO item_reference(from_kind, from_link_id, to_kind, to_link_id, role, origin, created_at)
SELECT DISTINCT 'message/rfc822', mi.link_id, 'text/calendar', e.link_id, 'invitation', 'auto',
       strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
FROM items mi
JOIN mail_summary s ON s.collection = mi.collection AND s.link_id = mi.link_id
JOIN items e ON e.link_id = s.invitation AND e.deleted = 0
JOIN collections ec ON ec.id = e.collection AND ec.kind = 'text/calendar'
WHERE mi.link_id BETWEEN coalesce(:link_id, '') AND coalesce(:link_id, x'') AND mi.deleted = 0
  AND NOT (mi.link_id GLOB 'alt:*' OR mi.link_id GLOB 'dup:*' OR mi.link_id GLOB 'hash:*') AND NOT (e.link_id GLOB 'alt:*' OR e.link_id GLOB 'dup:*' OR e.link_id GLOB 'hash:*')
ON CONFLICT DO NOTHING;
