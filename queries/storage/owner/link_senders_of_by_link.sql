-- link_senders_of over the mail the `links` slot names (§14.2), so a page of
-- mail runs the sender rule once rather than once per message: a reference
-- from each to every contact holding one of its `from` addresses as an
-- `email`, as link_senders_of records it.
INSERT INTO item_reference(from_kind, from_link_id, to_kind, to_link_id, role, origin, created_at)
SELECT DISTINCT 'message/rfc822', mi.link_id, 'text/vcard', ci.link_id, 'sender', 'auto',
       strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
FROM items mi
JOIN collections mc ON mc.id = mi.collection AND mc.kind = 'message/rfc822'
JOIN item_address m ON m.item = mi.id AND m.role = 'from'
JOIN item_address c ON c.address = m.address AND c.role = 'email'
JOIN items ci ON ci.id = c.item AND ci.deleted = 0
JOIN collections cc ON cc.id = ci.collection AND cc.kind = 'text/vcard'
WHERE mi.link_id IN (SELECT value FROM temp.param WHERE slot = 'links') AND mi.deleted = 0
  AND NOT (mi.link_id GLOB 'alt:*' OR mi.link_id GLOB 'dup:*' OR mi.link_id GLOB 'hash:*') AND NOT (ci.link_id GLOB 'alt:*' OR ci.link_id GLOB 'dup:*' OR ci.link_id GLOB 'hash:*')
ON CONFLICT DO NOTHING;
