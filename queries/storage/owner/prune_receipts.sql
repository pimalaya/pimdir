-- Drops the receipts applied before :before, an RFC 3339 instant (§13) at
-- least seven days back (§15.4): a producer that has not looked by then reads
-- its row as found nowhere.
DELETE FROM receipts WHERE applied_at < :before;
