-- What a message's body gave the rows of the account already holding it
-- (Annex A.1): the attachment mark and the invitation of a row of :link_id
-- whose item holds :object, so a placement gaining that body without reading
-- it (a copy, a move, a second label, an upgrade linking from the store)
-- states the body's columns, not those its listing read without it. A row
-- stating its mark comes first, then one stating an invitation; nothing when
-- no row of the account holds the body. A writer-derived key never matches,
-- as in lookup_objects (§9).
SELECT m.attachment, m.invitation FROM items i
JOIN collections c ON c.id = i.collection
JOIN mail_summary m ON m.collection = i.collection AND m.link_id = i.link_id
WHERE i.link_id = :link_id AND i.object_hash = :object
  AND i.link_id NOT LIKE 'alt:%' AND i.link_id NOT LIKE 'hash:%' AND i.link_id NOT LIKE 'dup:%'
  AND c.account IS :account
ORDER BY m.attachment IS NULL, m.invitation IS NULL, i.collection
LIMIT 1;
