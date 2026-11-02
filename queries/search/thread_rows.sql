-- The message rows of one thread with their parents and, for a message a
-- live mail placement holds, its lowest sort key, NULL for one none holds:
-- what a re-keying reads to find the connected sets left in a thread and
-- the present member naming each (§9).
SELECT m.link_id, m.parent,
       (SELECT min(i.sort_key) FROM placement p
        JOIN store.collections c ON c.id = p.collection AND c.kind = 'message/rfc822'
        JOIN store.items i ON i.collection = p.collection AND i.seq = p.seq
        WHERE p.link_id = m.link_id) AS sort_key
FROM message m WHERE m.thread = :thread ORDER BY m.link_id;
