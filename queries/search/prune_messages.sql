-- Within one thread, after unparent_messages, the message rows no live mail
-- placement holds and no row names as its parent (§9): what a rebuild from
-- the store as it stands would not write. Answers the ids it dropped.
DELETE FROM message
WHERE thread = :thread
  AND NOT EXISTS (SELECT 1 FROM placement p JOIN store.collections c ON c.id = p.collection
                  WHERE p.link_id = message.link_id AND c.kind = 'message/rfc822')
  AND NOT EXISTS (SELECT 1 FROM message r WHERE r.parent = message.link_id)
RETURNING link_id;
