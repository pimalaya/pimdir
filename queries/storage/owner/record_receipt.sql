-- Records what a queue row became, in the transaction removing it (§15.2,
-- §15.5): right after claim_action deleted an applied row, or cancel_action an
-- intent its performer acknowledges. The row's id, the collection it was queued
-- on, and the seq of the item the action acted on, the one it created for an
-- `add` (seq_by_link on the key it staged), a `move` and a `copy` (in their
-- target), or the item a performed intent left when known, NULL otherwise.
-- SQLite stamps applied_at.
INSERT INTO receipts(id, applied_at, collection, seq)
VALUES(:id, strftime('%Y-%m-%dT%H:%M:%fZ','now'), :collection, :seq);
