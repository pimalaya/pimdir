-- The In-Reply-To ids of the link ids in the `links` slot, in document order,
-- on load_addresses_by_link's terms (Annex A.1).
SELECT link_id, position, msg_id FROM mail_in_reply_to
WHERE collection = :collection
  AND link_id IN (SELECT value FROM temp.param WHERE slot = 'links')
ORDER BY link_id, position;
