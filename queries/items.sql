-- pimdir items: the shared per-item truth of a collection (flags, body pointer,
-- summary, detail level, cross-source state), plus public-id allocation and
-- retention, the soft delete every removal lands in (SPEC.md §11).
--
-- Reference statements for the store operations (SPEC.md §4.4, §14); column
-- encodings in §13, named parameters `:name`.

-- name: load_items
-- Retained items excluded: the sync seam sees live items only, and hiding them
-- here is what keeps one from being re-derived on a later sync (§11).
-- `sort_key` rides along although the sync layer has no use for it, because the
-- reference write is a replace-all: without it insert_item has nothing to bind
-- and every sync resets the ordering of every item it touched (§14).
SELECT link_id, flags, object_hash, meta, sort_key, level, deleted, conflicted, conflict_object
FROM items WHERE collection = :collection AND retained_at IS NULL;

-- name: load_items_by_link
-- Narrowed to the link ids one write batch touches. Reading the rest costs a
-- full pass over the collection to compute nothing, and that cost grows with
-- the mailbox rather than with the batch (§14).
SELECT link_id, flags, object_hash, meta, sort_key, level, deleted, conflicted, conflict_object
FROM items WHERE collection = :collection AND retained_at IS NULL
  AND link_id IN (SELECT value FROM json_each(:links));

-- name: delete_items
-- Clears a collection before it is re-saved (bindings cascade). Retained items
-- are spared, exactly as load_items skips them, so a replace-all cannot purge
-- by accident (§11).
DELETE FROM items WHERE collection = :collection AND retained_at IS NULL;

-- name: seq_for_link_any
-- The public id this link id already has, so all its placements share one.
-- Deliberately unscoped (§9.2): the seq is the short form of the link id, which
-- restates a fact the content carries and claims nothing about whether the
-- placements are one thing.
SELECT seq FROM items WHERE link_id = :link_id LIMIT 1;

-- name: bump_next_seq
-- Run only when the item has no id yet (seq_for_link_any returned nothing).
UPDATE store_meta SET next_seq = next_seq + 1 WHERE id = 1
RETURNING next_seq - 1;

-- name: insert_item
INSERT INTO items(collection, link_id, seq, flags, object_hash, meta, sort_key, level, deleted, conflicted, conflict_object)
VALUES(:collection, :link_id, :seq, :flags, :object_hash, :meta, :sort_key, :level, :deleted, :conflicted, :conflict_object);

-- The client read surface (§14.1): live-only reads keyed by the public id
-- (`seq`), never by the internal link id.

-- name: list_items_page
-- A keyset page in link-id order, riding the primary key with no extra index;
-- the empty string starts from the beginning, a link_id never being empty. That
-- order means nothing to a reader: it is the page for a sweep that must see
-- every item exactly once, and a listing wants a sort-key page below.
SELECT seq, link_id, flags, object_hash, meta, sort_key, level FROM items
WHERE collection = :collection AND deleted = 0 AND link_id > :after
ORDER BY link_id LIMIT :limit;

-- name: list_items_page_asc
-- A keyset page in the kind's own ascending order: A to Z for contacts,
-- earliest first for mail and calendars. The cursor is a pair because a sort
-- key is not unique; `seq` breaks the tie and, being unique per collection,
-- makes the page total. The empty string with seq 0 starts from the beginning.
SELECT seq, link_id, flags, object_hash, meta, sort_key, level FROM items
WHERE collection = :collection AND deleted = 0
  AND (sort_key, seq) > (:after_key, :after_seq)
ORDER BY sort_key, seq LIMIT :limit;

-- name: list_items_page_desc
-- The same page descending. Start by binding the largest key the store can
-- hold; an implementation SHOULD expose that as "no cursor" rather than make a
-- caller invent a sentinel.
SELECT seq, link_id, flags, object_hash, meta, sort_key, level FROM items
WHERE collection = :collection AND deleted = 0
  AND (sort_key, seq) < (:after_key, :after_seq)
ORDER BY sort_key DESC, seq DESC LIMIT :limit;

-- name: set_sort_key
-- Re-projects the key of an item already stored, for a kind whose convention
-- arrived or changed after the write. Ordinary writes carry it in insert_item.
UPDATE items SET sort_key = :sort_key
WHERE collection = :collection AND link_id = :link_id;

-- name: get_item
SELECT seq, link_id, flags, object_hash, meta, sort_key, level FROM items
WHERE collection = :collection AND seq = :seq AND deleted = 0;

-- name: count_items
SELECT count(*) FROM items WHERE collection = :collection AND deleted = 0;

-- The multiplicity reads (§9.2): where one identity, or one body, sits across
-- the store. They report a fact and take no position on it, a mail view listing
-- the placements where a contact view may offer to merge them.

-- name: list_link_placements
-- Pairs by the assigned key, not by the identity hint it came from, so a
-- minted copy (§9) is not listed beside the item holding the bare hint;
-- list_object_placements pairs those two whenever their bodies agree.
SELECT i.collection, c.account, i.seq, i.object_hash, i.flags, i.level
FROM items i JOIN collections c ON c.id = i.collection
WHERE i.link_id = :link_id AND i.deleted = 0 AND i.retained_at IS NULL
ORDER BY c.account IS NULL, c.account, i.collection;

-- name: list_object_placements
-- The dedup axis rather than the identity one (§9), so this finds the same
-- message delivered to two accounts even when the servers rewrote its link id.
SELECT i.collection, c.account, i.seq, i.link_id, i.flags, i.level
FROM items i JOIN collections c ON c.id = i.collection
WHERE i.object_hash = :hash AND i.deleted = 0 AND i.retained_at IS NULL
ORDER BY c.account IS NULL, c.account, i.collection;

-- name: seq_by_link
-- The inverse of get_item, for a consumer that just staged an add.
SELECT seq FROM items WHERE collection = :collection AND link_id = :link_id;

-- Retention (§11): an item whose last source binding vanished is retained,
-- never deleted; purge is the only true delete.

-- name: retain_item
-- The update that replaces the delete a hard-deleting store would issue. The
-- row keeps its object_hash, so the body stays pinned against the collector
-- (§5). SQLite stamps the instant; the cutoff of a later purge is the caller's.
UPDATE items SET deleted = 1,
                 retained_at = strftime('%Y-%m-%dT%H:%M:%fZ','now'),
                 retained_by = :source
WHERE collection = :collection AND link_id = :link_id;

-- name: revive_item
-- A link id that reappears revives the retained row holding its primary key
-- instead of conflicting on it, keeping its seq, so a restored item never gets
-- a second public id (§9.1). The caller adopts the new content in the same
-- transaction.
UPDATE items SET deleted = 0, retained_at = NULL, retained_by = NULL
WHERE collection = :collection AND link_id = :link_id;

-- name: list_retained_page
-- The trash listing, and the only read that returns retained items. :after is
-- the exclusive lower bound on `seq`, 0 starting from the beginning since seq
-- is handed out from 1: the cursor is the public id a reader already speaks
-- (§9.1), unlike the sweep page above, and it rides items_retained, which leads
-- with seq for this read. The size comes from the object the row still pins.
SELECT i.seq, i.link_id, i.flags, i.object_hash, i.meta, i.sort_key, i.level,
       i.retained_at, i.retained_by, o.size
FROM items i LEFT JOIN objects o ON o.hash = i.object_hash
WHERE i.collection = :collection AND i.retained_at IS NOT NULL AND i.seq > :after
ORDER BY i.seq LIMIT :limit;

-- name: count_retained
-- The counterpart of count_items, riding the items_retained partial index.
SELECT count(*) FROM items WHERE collection = :collection AND retained_at IS NOT NULL;

-- name: retained_bytes
-- The store-wide size of the bodies retention is holding, each object counted
-- once. An upper bound on what a purge reclaims: an object a live item also
-- points at keeps a reference and survives the collector (§5).
SELECT coalesce(sum(o.size), 0) FROM objects o WHERE o.hash IN
    (SELECT object_hash FROM items
     WHERE retained_at IS NOT NULL AND object_hash IS NOT NULL);

-- name: purge_item
-- The only true delete, guarded on retained_at so it can never take a live
-- item. It returns the two hashes the row pinned, so whoever deletes the row
-- settles them with release_pins in the same transaction rather than visiting
-- it twice; the bodies then fall to the collector (§5, §14).
DELETE FROM items
WHERE collection = :collection AND seq = :seq AND retained_at IS NOT NULL
RETURNING object_hash, conflict_object;

-- name: purge_retained_before
-- The time-based sweep, store-wide since how long to keep is the owner's policy
-- rather than a collection's. The cutoff (RFC 3339) is the caller's parameter,
-- not the store's clock, so the boundary is deterministic even though the stamp
-- is SQLite's. It returns pinned hashes on purge_item's terms.
DELETE FROM items WHERE retained_at IS NOT NULL AND retained_at < :cutoff
RETURNING object_hash, conflict_object;
