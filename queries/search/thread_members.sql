SELECT p.collection, p.seq FROM message m
JOIN placement p ON p.link_id = m.link_id
WHERE m.thread = :thread;
