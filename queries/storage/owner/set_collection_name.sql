-- What a collection is called, as opposed to how it is addressed. The id is
-- the key every foreign key cascades on and the name is a label, so this
-- moves one without touching the other. An owner namespacing its ids (§9.2)
-- records the bare name here, the separator being its own convention and not
-- one a reader can strip. Only the name is updated, so a declared kind and
-- the account survive.
INSERT INTO collections(id, account, kind, name)
VALUES(:collection, :account, '', :name)
ON CONFLICT(id) DO UPDATE SET name = excluded.name;
