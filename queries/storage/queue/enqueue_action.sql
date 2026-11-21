-- A producer's append. Runs after ensure_collection, in one transaction with
-- the store_object upsert when the payload references a body (§15). SQLite
-- stamps created_at (§13): the producer is a different process from the owner
-- and may be differently skewed, and ordering is `id` either way.
-- :target_collection is the collection the payload's `to` or
-- `supersedes.collection` names, NULL for any other action (§15.3). The body
-- is named by its hash and pinned by its objects.id: a hash no object row
-- holds resolves to 0, which the foreign key refuses.
INSERT INTO queue(created_at, producer, collection, action, payload, target_collection, object)
VALUES(strftime('%Y-%m-%dT%H:%M:%fZ','now'), :producer, :collection, :action, :payload,
       :target_collection,
       CASE WHEN :object_hash IS NULL THEN NULL ELSE coalesce((SELECT id FROM objects WHERE hash = :object_hash), 0) END);
