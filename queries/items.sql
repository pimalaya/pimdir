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

-- The client read surface (SPEC.md §12.1): live-only reads keyed by the public
-- id (`seq`), never by the internal link id.

-- name: list_items_page
-- A keyset page of a collection's live items. :after is the exclusive lower
-- bound on link_id (the empty string starts from the beginning, since a link_id
-- is never empty), so paging rides the items primary key with no extra index.
SELECT seq, link_id, flags, object_hash, meta, level FROM items
WHERE collection = :collection AND deleted = 0 AND link_id > :after
ORDER BY link_id LIMIT :limit;

-- name: get_item
-- One live item by its public id, the client-facing key.
SELECT seq, link_id, flags, object_hash, meta, level FROM items
WHERE collection = :collection AND seq = :seq AND deleted = 0;

-- name: count_items
-- A collection's live item count (tombstones excluded).
SELECT count(*) FROM items WHERE collection = :collection AND deleted = 0;

-- name: seq_by_link
-- Resolves an item's public id from its internal link id: the inverse of
-- get_item, for a consumer that just staged an add and wants the new id.
SELECT seq FROM items WHERE collection = :collection AND link_id = :link_id;
