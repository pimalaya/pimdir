-- What the collector takes (§5), and no write's business: the batch that
-- attaches a body may not be the one that indexed it. `<= 0` matches the
-- partial index objects_garbage, so neither statement scans, and it keeps the
-- read-only reader honest, since it cannot apply the refcount floor (§7).
SELECT hash FROM objects WHERE refcount <= 0;
