-- The candidates to perform an intent capability for an account (§15.6):
-- every source the owner declared for it whose row at the anchor
-- `:collection`, the collection's own or else the source-wide one, has some
-- support. With `:collection` NULL, every source supporting it anywhere in
-- the account, its source-wide row shown when it has one. Read from the
-- declaration rather than the synced collections, so a source is a
-- candidate before its first sync. `IS`, so NULL is a single-account
-- store's account.
SELECT c.source, c.support, c.detail
FROM capabilities c
WHERE c.account IS :account AND c.capability = :capability AND c.support <> 'none'
  AND (
    (:collection IS NULL AND (c.collection IS NULL OR NOT EXISTS (
        SELECT 1 FROM capabilities w
        WHERE w.source = c.source AND w.capability = c.capability
          AND w.collection IS NULL AND w.support <> 'none')))
    OR c.collection = :collection
    OR (c.collection IS NULL AND NOT EXISTS (
        SELECT 1 FROM capabilities o
        WHERE o.source = c.source AND o.capability = c.capability
          AND o.collection = :collection))
  )
GROUP BY c.source
ORDER BY c.source;
