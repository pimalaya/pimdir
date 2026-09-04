-- A producer's append. Runs after ensure_collection, in one transaction with
-- the store_object upsert when the payload references a body (§15). SQLite
-- stamps created_at (§13): the producer is a different process from the owner
-- and may be differently skewed, and ordering is `id` either way.
INSERT INTO queue(created_at, producer, collection, action, payload, object_hash)
VALUES(strftime('%Y-%m-%dT%H:%M:%fZ','now'), :producer, :collection, :action, :payload, :object_hash);
