-- Every stand-in of an account's attachments collection (§14.3, role
-- `attachments`; :account NULL for a single-account store) with the message
-- attaching it, newest message first, the files of one message by public id,
-- so a list of every attachment reads one statement. The message is read
-- from one live placement, its summary the same in each; a stand-in whose
-- message has none left is not listed. Cursor (message sort_key, stand-in
-- seq), a NULL :after_key the first page, coalesced to the empty blob above
-- every text. The collection is found by its role on collections_by_role and
-- its stand-ins by its key; the order is the messages', which no index of the
-- stand-ins holds, so every page reads the account's stand-ins once.
SELECT f.collection, f.seq, f.link_id, s.name, s.media_type, s.size, s.part,
       r.from_link_id AS message_link_id, m.collection AS message_collection, m.seq AS message_seq,
       m.sort_key AS message_sort_key, ms.sender, ms.sender_name, ms.date
FROM collections c
JOIN items f ON f.collection = c.id AND f.deleted = 0
LEFT JOIN file_summary s ON s.item = f.id
JOIN item_reference r ON r.to_link_id = f.link_id AND r.to_kind = 'application/octet-stream'
                     AND r.role = 'attachment' AND r.from_kind = 'message/rfc822'
JOIN items m ON m.rowid = (SELECT x.rowid FROM items x JOIN collections xc ON xc.id = x.collection
                           WHERE x.link_id = r.from_link_id AND x.deleted = 0
                             AND xc.kind = 'message/rfc822'
                           LIMIT 1)
LEFT JOIN mail_summary ms ON ms.item = m.id
WHERE ifnull(c.account, '') = ifnull(:account, '') AND c.account IS :account
  AND c.kind = 'application/octet-stream' AND c.role = 'attachments'
  AND (m.sort_key, f.seq) < (coalesce(:after_key, x''), coalesce(:after_seq, 0))
ORDER BY m.sort_key DESC, f.seq DESC LIMIT :limit;
