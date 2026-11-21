-- A placement, by its key, naming its body by hash, NULL while it holds none
-- indexed (§4). The body is the object row insert_object wrote first: a hash
-- the index does not hold resolves to 0, which placement's CHECK refuses.
INSERT INTO placement(collection, seq, link_id, object)
VALUES(:collection, :seq, :link_id,
       CASE WHEN :hash IS NULL THEN NULL ELSE coalesce((SELECT id FROM object WHERE hash = :hash), 0) END)
ON CONFLICT(collection, seq) DO UPDATE SET link_id = excluded.link_id, object = excluded.object
RETURNING id;
