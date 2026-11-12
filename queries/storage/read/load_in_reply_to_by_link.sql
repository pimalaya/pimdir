-- The In-Reply-To ids of the link ids in the `links` slot, in document order,
-- on load_addresses_by_link's terms (Annex A.1).
SELECT i.link_id, r.position, r.message_id
FROM items i JOIN mail_in_reply_to r ON r.item = i.id
WHERE i.collection = :collection
  AND i.link_id IN (SELECT value FROM temp.param WHERE slot = 'links')
ORDER BY i.link_id, r.position;
