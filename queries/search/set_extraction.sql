-- The revisions the index now stands under (§2): §6's and the indexer's own,
-- written in the transaction that extracted the last held body again.
UPDATE index_meta SET extraction = :extraction, extractor = :extractor WHERE id = 1;
