INSERT INTO contact_summary(collection, link_id, uid, fn, kind, org)
VALUES(:collection, :link_id, :uid, :fn, :kind, :org)
ON CONFLICT(collection, link_id) DO UPDATE SET
    uid = excluded.uid, fn = excluded.fn, kind = excluded.kind, org = excluded.org;
