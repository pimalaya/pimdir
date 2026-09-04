INSERT INTO placement(collection, seq, link_id, hash) VALUES(:collection, :seq, :link_id, :hash)
ON CONFLICT(collection, seq) DO UPDATE SET link_id = excluded.link_id, hash = excluded.hash
RETURNING rowid;
