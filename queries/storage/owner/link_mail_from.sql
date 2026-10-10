-- The sender rule from the other end (§14.2): the references
-- link_senders_of records, for the mail from any `email` of one contact, so
-- a contact added today, or given an address, has its history. :link_id
-- names the contact, NULL every contact, on link_senders_of's range. An
-- address removed removes nothing.
INSERT INTO item_reference(from_kind, from_link_id, to_kind, to_link_id, role, origin, created_at)
SELECT DISTINCT 'message/rfc822', mi.link_id, 'text/vcard', ci.link_id, 'sender', 'auto',
       strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
FROM items ci
JOIN collections cc ON cc.id = ci.collection AND cc.kind = 'text/vcard'
JOIN item_address c ON c.collection = ci.collection AND c.link_id = ci.link_id AND c.role = 'email'
JOIN item_address m ON m.address = c.address AND m.role = 'from'
JOIN collections mc ON mc.id = m.collection AND mc.kind = 'message/rfc822'
JOIN items mi ON mi.collection = m.collection AND mi.link_id = m.link_id AND mi.deleted = 0
WHERE ci.link_id BETWEEN coalesce(:link_id, '') AND coalesce(:link_id, x'') AND ci.deleted = 0
  AND NOT (mi.link_id GLOB 'alt:*' OR mi.link_id GLOB 'dup:*' OR mi.link_id GLOB 'hash:*') AND NOT (ci.link_id GLOB 'alt:*' OR ci.link_id GLOB 'dup:*' OR ci.link_id GLOB 'hash:*')
ON CONFLICT DO NOTHING;
