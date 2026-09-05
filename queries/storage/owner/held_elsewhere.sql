-- Whether another collection of the same account holds an identity live with
-- the same body, so the drop of its last binding here is a move, not a loss
-- (§11). A retiring row with no body is held by any live holder; one with a
-- body needs a holder carrying that body, else the holder is bodiless or
-- diverged and the row is retained.
SELECT 1 FROM items AS held
JOIN collections AS there ON there.id = held.collection
JOIN collections AS here ON here.id = :collection
WHERE held.link_id = :link_id AND held.collection != :collection
  AND held.deleted = 0
  AND (:object IS NULL OR held.object_hash = :object)
  AND there.account IS here.account
LIMIT 1;
