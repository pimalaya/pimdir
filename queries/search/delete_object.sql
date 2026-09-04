-- The FTS row is deleted by rowid first (contentless_delete), then the row.
DELETE FROM object_text WHERE rowid = :rowid;
