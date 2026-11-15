-- Drops the receipts applied before :before, an RFC 3339 instant (§13) at
-- least seven days back (§15.4): a producer that has not looked by then reads
-- its row as found nowhere. A receipt whose item a refusal stands on is kept,
-- read as load_receipt_refusals reads it, until the refusal is cleared or its
-- binding goes.
DELETE FROM receipts WHERE applied_at < :before
  AND NOT EXISTS (
      SELECT 1 FROM collections q
      JOIN items i ON i.seq = receipts.seq
      JOIN collections c ON c.id = i.collection AND c.account IS q.account
      JOIN bindings b ON b.item = i.id
      WHERE q.id = receipts.collection AND b.refusal IS NOT NULL
  );
