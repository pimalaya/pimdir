-- The In-Reply-To ids of a collection's mail, or with :scoped 1 of the link
-- ids in the `links` slot, in document order: what a mail row carries beside
-- its summary (Annex A.1), on load_addresses_by_link's terms.
SELECT link_id, position, msg_id FROM mail_in_reply_to
WHERE collection = :collection
  AND (:scoped = 0 OR link_id IN (SELECT value FROM temp.param WHERE slot = 'links'))
ORDER BY link_id, position;
