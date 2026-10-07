-- Stamps the bindings of the handles a page listed (:handles, a JSON array)
-- with the open round's id, in the page's write and after its upserts, so a
-- member the page named is stamped too (SYNC.md §5). A listed member that
-- moved nothing still needs its stamp: the round's last page drops what no
-- page stamped.
UPDATE bindings SET round = (SELECT round FROM sources
                             WHERE collection = :collection AND source = :source)
WHERE collection = :collection AND source = :source
  AND handle IN (SELECT value FROM json_each(:handles));
