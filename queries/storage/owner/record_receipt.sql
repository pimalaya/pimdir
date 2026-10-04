-- Records what an applied action became, in the transaction applying it, right
-- after claim_action deleted its row (§15.2): the row's id, the collection it
-- was queued on, and for an `add` the seq of the item it created (seq_by_link
-- on the key it staged), NULL for every other kind. SQLite stamps applied_at.
INSERT INTO receipts(id, applied_at, collection, seq)
VALUES(:id, strftime('%Y-%m-%dT%H:%M:%fZ','now'), :collection, :seq);
