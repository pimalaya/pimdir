-- Guarantees the FK target exists before a source, item or checkpoint write.
-- Binds the account too, since a collection that appears without one is
-- invisible to every by-account read until it is set.
INSERT INTO collections(id, account, kind, name)
VALUES(:collection, :account, '', :collection)
ON CONFLICT(id) DO NOTHING;
