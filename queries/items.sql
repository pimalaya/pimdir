-- pimdir items: the shared per-item truth of a collection (flags, body pointer,
-- summary, detail level, cross-source state), plus public-id (`seq`) allocation
-- and retention, the soft delete every removal lands in (SPEC.md §11).
--
-- Canonical reference statements servicing the store operations (SPEC.md §14).
-- An implementation SHOULD use them verbatim and MAY substitute an equivalent
-- that preserves the same invariants (SPEC.md §7). Column encodings are in
-- SPEC.md §13. Named parameters use `:name`.

-- name: load_items
-- Every shared item of a collection, retained ones excluded: the sync seam sees
-- live items only. Hiding a retained row here is what keeps it from ever being
-- re-derived, on a delta or on a full sync (SPEC.md §11).
--
-- `sort_key` rides along although the sync layer has no use for it, because the
-- reference write is a replace-all (SPEC.md §14): load, merge, delete, insert.
-- Without it here, insert_item would have nothing to bind and every sync would
-- silently reset the ordering of every item it touched.
SELECT link_id, flags, object_hash, meta, sort_key, level, deleted, conflicted, conflict_object
FROM items WHERE collection = :collection AND retained_at IS NULL;

-- name: load_items_by_link
-- The same rows, narrowed to the link ids one write batch touches (SPEC.md §14).
-- A write folds its batch into the collection and persists the difference, and
-- that difference only ever names rows the batch named: reading the rest costs a
-- full pass over the collection to compute nothing. It is the whole cost of a
-- small write, and it grows with the mailbox rather than with the batch.
SELECT link_id, flags, object_hash, meta, sort_key, level, deleted, conflicted, conflict_object
FROM items WHERE collection = :collection AND retained_at IS NULL
  AND link_id IN (SELECT value FROM json_each(:links));

-- name: delete_items
-- Clears a collection's items before it is re-saved (bindings cascade).
-- Retained items are spared, exactly as load_items skips them: the merged
-- result never contains one, so a replace-all that took them would purge by
-- accident (SPEC.md §11).
DELETE FROM items WHERE collection = :collection AND retained_at IS NULL;

-- name: seq_for_link_any
-- The message's existing public id, if any placement of this link_id already has
-- one (in any collection, of any account), so all placements of one link id
-- share one id.
--
-- Deliberately unscoped (SPEC.md §9.2): the seq is the short form of the link
-- id, so equal link ids share it wherever they sit. That is a restatement of a
-- fact the content carries, not a claim that the placements are one thing;
-- whether they are is the interface's call, made from list_link_placements.
SELECT seq FROM items WHERE link_id = :link_id LIMIT 1;

-- name: bump_next_seq
-- Hands out (and advances) the store-global next public id. The counter only ever
-- increases, so a `seq` is never reused. Run only when the message has no id yet
-- (seq_for_link_any returned nothing).
UPDATE store_meta SET next_seq = next_seq + 1 WHERE id = 1
RETURNING next_seq - 1;

-- name: insert_item
INSERT INTO items(collection, link_id, seq, flags, object_hash, meta, sort_key, level, deleted, conflicted, conflict_object)
VALUES(:collection, :link_id, :seq, :flags, :object_hash, :meta, :sort_key, :level, :deleted, :conflicted, :conflict_object);

-- The client read surface (SPEC.md §14.1): live-only reads keyed by the public
-- id (`seq`), never by the internal link id.

-- name: list_items_page
-- A keyset page of a collection's live items in link-id order. :after is the
-- exclusive lower bound on link_id (the empty string starts from the beginning,
-- since a link_id is never empty), so paging rides the items primary key with no
-- extra index.
--
-- Link-id order is arbitrary to a reader. It is the right page for a sweep that
-- must see every item exactly once (an export, a re-projection); a reader
-- presenting a list wants one of the two sort-key pages below.
SELECT seq, link_id, flags, object_hash, meta, sort_key, level FROM items
WHERE collection = :collection AND deleted = 0 AND link_id > :after
ORDER BY link_id LIMIT :limit;

-- name: list_items_page_asc
-- A keyset page of a collection's live items in the kind's own ascending order
-- (SPEC.md §14.1): A to Z for contacts, earliest first for mail and calendars.
--
-- The cursor is the pair (:after_key, :after_seq), because a sort key is not
-- unique: two messages share a timestamp, two contacts share a name. `seq`
-- breaks the tie, and being unique per collection it makes the page total. The
-- empty string with seq 0 starts from the beginning, since no real key sorts
-- before an unknown one ascending.
SELECT seq, link_id, flags, object_hash, meta, sort_key, level FROM items
WHERE collection = :collection AND deleted = 0
  AND (sort_key, seq) > (:after_key, :after_seq)
ORDER BY sort_key, seq LIMIT :limit;

-- name: list_items_page_desc
-- The same page descending: newest first for mail and calendars, Z to A for
-- contacts. Start from the beginning by binding the largest key the store can
-- hold; an implementation SHOULD expose this as "no cursor" rather than make a
-- caller invent a sentinel.
SELECT seq, link_id, flags, object_hash, meta, sort_key, level FROM items
WHERE collection = :collection AND deleted = 0
  AND (sort_key, seq) < (:after_key, :after_seq)
ORDER BY sort_key DESC, seq DESC LIMIT :limit;

-- name: set_sort_key
-- Restates one item's ordering key, for a re-projection that derives sort keys
-- for items already stored (a store written before the kind had a convention, or
-- one whose convention changed). Ordinary writes carry it in insert_item.
UPDATE items SET sort_key = :sort_key
WHERE collection = :collection AND link_id = :link_id;

-- name: get_item
-- One live item by its public id, the client-facing key.
SELECT seq, link_id, flags, object_hash, meta, sort_key, level FROM items
WHERE collection = :collection AND seq = :seq AND deleted = 0;

-- name: count_items
-- A collection's live item count (tombstones excluded).
SELECT count(*) FROM items WHERE collection = :collection AND deleted = 0;

-- The multiplicity reads (SPEC.md §9.2): where one identity, or one body, sits
-- across the whole store. They report a fact and take no position on it: a mail
-- view lists the placements, a contact view may offer to merge them, and both
-- read the same rows.

-- name: list_link_placements
-- Every live placement of one link id, with the collection and account it sits
-- in. The same vCard UID in two address books of two accounts returns two rows;
-- what that means is the caller's to decide.
SELECT i.collection, c.account, i.seq, i.object_hash, i.flags, i.level
FROM items i JOIN collections c ON c.id = i.collection
WHERE i.link_id = :link_id AND i.deleted = 0 AND i.retained_at IS NULL
ORDER BY c.account IS NULL, c.account, i.collection;

-- name: list_object_placements
-- Every live placement of one body, by content hash. The dedup axis rather than
-- the identity one (SPEC.md §9): identical bytes, whoever received them, so
-- this finds the same message delivered to two accounts even when the two
-- servers rewrote its link id.
SELECT i.collection, c.account, i.seq, i.link_id, i.flags, i.level
FROM items i JOIN collections c ON c.id = i.collection
WHERE i.object_hash = :hash AND i.deleted = 0 AND i.retained_at IS NULL
ORDER BY c.account IS NULL, c.account, i.collection;

-- name: seq_by_link
-- Resolves an item's public id from its internal link id: the inverse of
-- get_item, for a consumer that just staged an add and wants the new id.
SELECT seq FROM items WHERE collection = :collection AND link_id = :link_id;

-- Retention (SPEC.md §11): an item whose last source binding vanished is
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
-- A keyset page of a collection's retained items: the trash listing, and the
-- only read that returns them. :after is the exclusive lower bound on `seq`,
-- and 0 starts from the beginning, since seq is handed out from 1.
--
-- On seq rather than on link_id, unlike list_items_page above. That one is the
-- sweep read, where an arbitrary total order is what is wanted; this one is a
-- listing a reader presents, so its cursor is the public id the reader already
-- speaks (SPEC.md §9.1, §14.1) rather than the internal key. It also rides
-- items_retained, which leads with seq for this read: ordering by anything else
-- sorts every retained row in the collection to return one page.
--
-- The body size comes from the object the row still pins, NULL when unhydrated.
SELECT i.seq, i.link_id, i.flags, i.object_hash, i.meta, i.sort_key, i.level,
       i.retained_at, i.retained_by, o.size
FROM items i LEFT JOIN objects o ON o.hash = i.object_hash
WHERE i.collection = :collection AND i.retained_at IS NOT NULL AND i.seq > :after
ORDER BY i.seq LIMIT :limit;

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
-- (list_garbage_objects / delete_garbage_objects, SPEC.md §5, §14). Guarded on
-- retained_at so a purge can never take a live item.
DELETE FROM items
WHERE collection = :collection AND seq = :seq AND retained_at IS NOT NULL;

-- name: purge_retained_before
-- The time-based sweep: every item retired before :cutoff (RFC 3339). The
-- cutoff is the caller's parameter, not the store's clock, so the boundary is
-- deterministic even though the stamp is SQLite's. Store-wide, since how long
-- to keep is the owner's policy rather than a collection's.
DELETE FROM items WHERE retained_at IS NOT NULL AND retained_at < :cutoff;
