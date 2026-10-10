-- The sender rule (§14.2): a reference from a mail to every contact holding
-- one of its `from` addresses as an `email`, role `sender`, origin `auto`,
-- both ends live and neither under a writer-derived key, which names no
-- identity (§9). :link_id names the mail, NULL every mail (a backfill): the
-- range is one key or, open, the whole of items_by_link. A reference already
-- recorded is left as it is, a person's included.
INSERT INTO item_reference(from_kind, from_link_id, to_kind, to_link_id, role, origin, created_at)
SELECT DISTINCT 'message/rfc822', mi.link_id, 'text/vcard', ci.link_id, 'sender', 'auto',
       strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
FROM items mi
JOIN collections mc ON mc.id = mi.collection AND mc.kind = 'message/rfc822'
JOIN item_address m ON m.collection = mi.collection AND m.link_id = mi.link_id AND m.role = 'from'
JOIN item_address c ON c.address = m.address AND c.role = 'email'
JOIN collections cc ON cc.id = c.collection AND cc.kind = 'text/vcard'
JOIN items ci ON ci.collection = c.collection AND ci.link_id = c.link_id AND ci.deleted = 0
WHERE mi.link_id BETWEEN coalesce(:link_id, '') AND coalesce(:link_id, x'') AND mi.deleted = 0
  AND NOT (mi.link_id GLOB 'alt:*' OR mi.link_id GLOB 'dup:*' OR mi.link_id GLOB 'hash:*') AND NOT (ci.link_id GLOB 'alt:*' OR ci.link_id GLOB 'dup:*' OR ci.link_id GLOB 'hash:*')
ON CONFLICT DO NOTHING;
