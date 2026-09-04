-- The empty string means the row was created lazily by a sync and no kind was
-- ever declared (§14).
SELECT kind FROM collections WHERE id = :collection;
