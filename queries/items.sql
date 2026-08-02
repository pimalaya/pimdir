-- pimdir items: the shared per-item truth of a collection (flags, body pointer,
-- summary, detail level, cross-source state), plus public-id (`seq`) allocation.
--
-- Canonical reference statements servicing the store operations (SPEC.md §12).
-- An implementation SHOULD use them verbatim and MAY substitute an equivalent
-- that preserves the same invariants (SPEC.md §8). Column encodings are in
-- SPEC.md §11. Named parameters use `:name`.

-- name: load_items
-- Every shared item of a collection.
SELECT link_id, flags, object_hash, meta, level, deleted, conflicted, conflict_object
FROM items WHERE collection = :collection;

-- name: delete_items
-- Clears a collection's items before it is re-saved (bindings cascade).
DELETE FROM items WHERE collection = :collection;

-- name: seq_for_link_any
-- The message's existing public id, if any placement of this link_id already has
-- one (in any collection), so all placements of a message share one id.
SELECT seq FROM items WHERE link_id = :link_id LIMIT 1;

-- name: bump_next_seq
-- Hands out (and advances) the store-global next public id. The counter only ever
-- increases, so a `seq` is never reused. Run only when the message has no id yet
-- (seq_for_link_any returned nothing).
UPDATE store_meta SET next_seq = next_seq + 1 WHERE id = 1
RETURNING next_seq - 1;

-- name: insert_item
INSERT INTO items(collection, link_id, seq, flags, object_hash, meta, level, deleted, conflicted, conflict_object)
VALUES(:collection, :link_id, :seq, :flags, :object_hash, :meta, :level, :deleted, :conflicted, :conflict_object);
