-- Gives every binding written before shared_object existed the item's own body
-- as its agreement point, once the column has been added under the §6 draft
-- allowance. Left empty the column reads as "this source has never folded",
-- which falls back to the sync base, and a binding whose push is pending sits
-- behind the shared body by definition: the first absorb after the upgrade
-- would measure the cross-source axis from the base again and file the source's
-- own next edit as a divergence (§13). An existing store's sources agree with
-- the body they hold, so that body is what the rows already imply. Guarded on
-- IS NULL, which is every row of a column just added and no row of one already
-- backfilled, so running it twice is a no-op.
UPDATE bindings SET shared_object =
       (SELECT object_hash FROM items
        WHERE items.collection = bindings.collection AND items.link_id = bindings.link_id)
WHERE shared_object IS NULL;
