INSERT INTO contact_summary(item, uid, fn, kind, org)
VALUES((SELECT id FROM items WHERE collection = :collection AND link_id = :link_id), :uid, :fn, :kind, :org)
ON CONFLICT(item) DO UPDATE SET
    uid = excluded.uid, fn = excluded.fn, kind = excluded.kind, org = excluded.org;
