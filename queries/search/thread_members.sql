-- The present members of a thread in one account (§9): phantom message rows
-- have no placement and two accounts holding one message id are two threads
-- to a client.
SELECT p.collection, p.seq FROM message m
JOIN placement p ON p.link_id = m.link_id
JOIN store.collections c ON c.id = p.collection
WHERE m.thread = :thread AND c.account IS :account;
