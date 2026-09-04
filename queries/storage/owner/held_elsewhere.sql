-- Whether another collection of the same account holds an identity live, so
-- the drop of its last binding here is a move, not a loss (§11).
SELECT 1 FROM items AS held
JOIN collections AS there ON there.id = held.collection
JOIN collections AS here ON here.id = :collection
WHERE held.link_id = :link_id AND held.collection != :collection
  AND held.deleted = 0 AND held.retained_at IS NULL
  AND there.account IS here.account
LIMIT 1;
