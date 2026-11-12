-- What a message's body gave the rows of the account already holding it
-- (Annex A.1): the attachment mark and the invitation of a row of :link_id
-- whose item holds :hash, so a placement gaining that body without reading
-- it (a copy, a move, a second label, an upgrade linking from the store)
-- states the body's columns, not those its listing read without it. A row
-- stating its mark comes first, then one stating an invitation; nothing when
-- no row of the account holds the body. A writer-derived key never matches,
-- as in lookup_objects (§9).
SELECT m.attachment, m.invitation FROM items i
JOIN collections c ON c.id = i.collection
JOIN mail_summary m ON m.item = i.id
WHERE i.link_id = :link_id AND i.object_hash = :hash
  AND NOT (i.link_id GLOB 'alt:*' OR i.link_id GLOB 'hash:*' OR i.link_id GLOB 'dup:*')
  AND c.account IS :account
ORDER BY m.attachment IS NULL, m.invitation IS NULL, i.collection
LIMIT 1;
