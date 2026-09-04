-- Unlike ensure_collection this is deliberate, so it does overwrite a kind
-- already declared; the row's name is untouched.
INSERT INTO collections(id, account, kind, name)
VALUES(:collection, :account, :kind, :collection)
ON CONFLICT(id) DO UPDATE SET kind = excluded.kind;
