-- The live placements whose system flags lack `\Seen` (§8): is:unread, read
-- from the store's items.marks as it stands, never from the index, so it
-- answers a flag the index has yet to fold (§8.2). A hit matches when none
-- of its placements holds the bit, so one also holding a read placement is
-- left out by the client. The test is spelled as items_unread states it, the
-- partial index named: it holds the unread rows alone, so a store mostly read
-- walks few. A row whose flag set is unknown holds no bit (STORAGE §13).
SELECT i.collection, i.seq FROM store.items i INDEXED BY items_unread
WHERE i.deleted = 0 AND i.marks & 1 = 0;
