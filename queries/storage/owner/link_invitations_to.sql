-- The invitation rule from the other end (§14.2): the references
-- link_invitations_of records, for the mail inviting to one calendar item,
-- so an event synced after its invitation is still tied to it. :link_id
-- names the calendar item, NULL every one, on link_senders_of's range;
-- mail_summary_by_invitation finds the mail.
INSERT INTO item_reference(from_kind, from_link_id, to_kind, to_link_id, role, origin, created_at)
SELECT DISTINCT 'message/rfc822', mi.link_id, 'text/calendar', e.link_id, 'invitation', 'auto',
       strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
FROM items e
JOIN collections ec ON ec.id = e.collection AND ec.kind = 'text/calendar'
JOIN mail_summary s ON s.invitation = e.link_id
JOIN items mi ON mi.collection = s.collection AND mi.link_id = s.link_id AND mi.deleted = 0
WHERE e.link_id BETWEEN coalesce(:link_id, '') AND coalesce(:link_id, x'') AND e.deleted = 0
ON CONFLICT DO NOTHING;
