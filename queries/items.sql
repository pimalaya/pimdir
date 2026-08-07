-- pimdir items: the shared per-item truth of a collection (flags, body pointer,
-- summary, detail level, cross-source state), plus public-id (`seq`) allocation
-- and retention, the soft delete every removal lands in (SPEC.md §16).
--
-- Canonical reference statements servicing the store operations (SPEC.md §12).
-- An implementation SHOULD use them verbatim and MAY substitute an equivalent
-- that preserves the same invariants (SPEC.md §8). Column encodings are in
-- SPEC.md §11. Named parameters use `:name`.

-- name: load_items
-- Every shared item of a collection, retained ones excluded: the sync seam sees
-- live items only. Hiding a retained row here is what keeps it from ever being
-- re-derived, on a delta or on a full sync (SPEC.md §16).
SELECT link_id, flags, object_hash, meta, level, deleted, conflicted, conflict_object
FROM items WHERE collection = :collection AND retained_at IS NULL;

-- name: delete_items
-- Clears a collection's items before it is re-saved (bindings cascade).
-- Retained items are spared, exactly as load_items skips them: the merged
-- result never contains one, so a replace-all that took them would purge by
-- accident (SPEC.md §16).
DELETE FROM items WHERE collection = :collection AND retained_at IS NULL;

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

-- Retention (SPEC.md §16): an item whose last source binding vanished is
-- retained, never deleted; purge is the only true delete.

-- name: retain_item
-- Retire an item: the update that replaces the delete a hard-deleting store
-- would issue when the last source binding goes. The row keeps its object_hash,
-- so the body keeps its reference and its blob survives the sweep (SPEC.md §5).
-- SQLite stamps the instant itself, so no implementation plumbs a clock through
-- to reach this statement; the cutoff of a later purge is the caller's.
UPDATE items SET deleted = 1,
                 retained_at = strftime('%Y-%m-%dT%H:%M:%fZ','now'),
                 retained_by = :source
WHERE collection = :collection AND link_id = :link_id;

-- name: revive_item
-- A link id that reappears (a source-side resurrection, or a client `add`)
-- revives the retained row holding its primary key instead of conflicting on
-- it. The row keeps its seq, so a restored item never gets a second public id
-- (SPEC.md §9.1); the caller adopts the new content in the same transaction.
UPDATE items SET deleted = 0, retained_at = NULL, retained_by = NULL
WHERE collection = :collection AND link_id = :link_id;

-- name: list_retained_page
-- A keyset page of a collection's retained items: the trash listing beside
-- list_items_page, and the only read that returns them. Same :after contract,
-- the exclusive lower bound on link_id, so paging rides the items primary key.
-- The body size comes from the object the row still pins, NULL when unhydrated.
SELECT i.seq, i.link_id, i.flags, i.object_hash, i.meta, i.level,
       i.retained_at, i.retained_by, o.size
FROM items i LEFT JOIN objects o ON o.hash = i.object_hash
WHERE i.collection = :collection AND i.retained_at IS NOT NULL AND i.link_id > :after
ORDER BY i.link_id LIMIT :limit;

-- name: count_retained
-- A collection's retained item count, the counterpart of count_items. Rides the
-- items_retained partial index.
SELECT count(*) FROM items WHERE collection = :collection AND retained_at IS NOT NULL;

-- name: retained_bytes
-- The store-wide size of the bodies retention is holding, each distinct object
-- counted once (two retained placements of one message share it). An upper
-- bound on what a purge reclaims: an object a live item also points at keeps a
-- reference and survives the sweep (SPEC.md §5).
SELECT coalesce(sum(o.size), 0) FROM objects o WHERE o.hash IN
    (SELECT object_hash FROM items
     WHERE retained_at IS NOT NULL AND object_hash IS NOT NULL);

-- name: purge_item
-- Purge one retained item by its public id: the only true delete. Its bindings
-- cascade, and the body it released is unlinked by the ordinary refcount sweep
-- (list_garbage_objects / delete_garbage_objects, SPEC.md §5, §12). Guarded on
-- retained_at so a purge can never take a live item.
DELETE FROM items
WHERE collection = :collection AND seq = :seq AND retained_at IS NOT NULL;

-- name: purge_retained_before
-- The time-based sweep: every item retired before :cutoff (RFC 3339). The
-- cutoff is the caller's parameter, not the store's clock, so the boundary is
-- deterministic even though the stamp is SQLite's. Store-wide, since how long
-- to keep is the owner's policy rather than a collection's.
DELETE FROM items WHERE retained_at IS NOT NULL AND retained_at < :cutoff;
