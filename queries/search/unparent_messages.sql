-- Within one thread, a message row no live mail placement holds names no
-- parent (§9): the headers it was read from are no member's any more. Run
-- before prune_messages, on the thread of a message whose last placement
-- went.
UPDATE message SET parent = NULL
WHERE thread = :thread AND parent IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM placement p JOIN store.collections c ON c.id = p.collection
                  WHERE p.link_id = message.link_id AND c.kind = 'message/rfc822');
