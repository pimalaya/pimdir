-- The placements whose indexed body holds text in its attachment field (§6):
-- has:attachment for a calendar item, a mail answering by its mark on the
-- store (§8).
SELECT p.collection, p.seq FROM placement p JOIN object o ON o.hash = p.hash
WHERE o.attachment = 1;
