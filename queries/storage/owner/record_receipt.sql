-- Records what a queue row became, in the transaction removing it (§15.2,
-- §15.5): right after claim_action deleted an applied row, or cancel_action an
-- intent its performer acknowledges. The row's id, the collection it was queued
-- on, and the seq of the item an `add` created (seq_by_link on the key it
-- staged) or a performed intent left when known, NULL otherwise. SQLite stamps
-- applied_at.
INSERT INTO receipts(id, applied_at, collection, seq)
VALUES(:id, strftime('%Y-%m-%dT%H:%M:%fZ','now'), :collection, :seq);
