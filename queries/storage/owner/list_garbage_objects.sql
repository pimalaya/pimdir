-- What the collector takes (§5), after recompute_refcounts has settled every
-- count, and no write's business: the batch that attaches a body may not be
-- the one that indexed it. `<= 0` matches the partial index objects_garbage,
-- so neither statement scans.
SELECT hash FROM objects WHERE refcount <= 0;
