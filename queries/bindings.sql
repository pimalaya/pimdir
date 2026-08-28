-- pimdir bindings: one source's binding of an item, its handle there, the two
-- bases it agreed from (the three-way-merge base and the shared body it last
-- reconciled against), and whether that source's own sync is stuck on an
-- unresolved content conflict.
--
-- Reference statements for the store operations (SPEC.md §4.4, §14); column
-- encodings in §13, named parameters `:name`.

-- name: load_bindings
SELECT link_id, source, handle, base_flags, base_object, base_revision,
       base_present, conflicted, conflict_revision, conflict_object, shared_object
FROM bindings WHERE collection = :collection;

-- name: load_bindings_by_link
-- Narrowed to the link ids one write batch touches: the binding half of
-- load_items_by_link (queries/items.sql).
SELECT link_id, source, handle, base_flags, base_object, base_revision,
       base_present, conflicted, conflict_revision, conflict_object, shared_object
FROM bindings WHERE collection = :collection
  AND link_id IN (SELECT value FROM json_each(:links));

-- name: insert_binding
INSERT INTO bindings(collection, link_id, source, handle, base_flags, base_object,
                     base_revision, base_present, conflicted, conflict_revision,
                     conflict_object, shared_object)
VALUES(:collection, :link_id, :source, :handle, :base_flags, :base_object,
       :base_revision, :base_present, :conflicted, :conflict_revision,
       :conflict_object, :shared_object);

-- name: update_binding
-- `handle` is deliberately absent: repointing it is how a source holding one
-- identity twice used to be destroyed, silently, at the write. A write that
-- resolves this binding to another handle is refused instead (§10), the second
-- copy having a key and an item of its own (§9); a legitimate rebind goes
-- through the handle-space rebuild.
UPDATE bindings SET base_flags = :base_flags, base_object = :base_object,
       base_revision = :base_revision, base_present = :base_present,
       conflicted = :conflicted, conflict_revision = :conflict_revision,
       conflict_object = :conflict_object, shared_object = :shared_object
WHERE collection = :collection AND link_id = :link_id AND source = :source;

-- name: backfill_shared_object
-- Gives every binding written before shared_object existed the item's own body
-- as its agreement point, once the column has been added under the §6 draft
-- allowance. Left empty the column reads as "this source has never folded",
-- which falls back to the sync base, and a binding whose push is pending sits
-- behind the shared body by definition: the first absorb after the upgrade
-- would measure the cross-source axis from the base again and file the source's
-- own next edit as a divergence (§13). An existing store's sources agree with
-- the body they hold, so that body is what the rows already imply. Guarded on
-- IS NULL, which is every row of a column just added and no row of one already
-- backfilled, so running it twice is a no-op.
UPDATE bindings SET shared_object =
       (SELECT object_hash FROM items
        WHERE items.collection = bindings.collection AND items.link_id = bindings.link_id)
WHERE shared_object IS NULL;

-- The client read surface (§14.1).

-- name: list_sources
-- Read from bindings rather than sources, so a source appears as soon as it
-- holds one item, without waiting for a checkpoint row.
SELECT DISTINCT source FROM bindings ORDER BY source;

-- name: list_conflicted_bindings
-- The bindings waiting for a decision, across one account's collections: what
-- each one is, and the three bodies a resolver merges. The base is what the two
-- sides last agreed on, the item's own object_hash is the local side, and
-- conflict_object is the remote one at conflict_revision, so a resolver holding
-- no credentials reads the whole divergence from the store (§13).
-- Rides bindings_conflicted, which holds only the outstanding rows: a run
-- reports this count on every invocation, and answering it by paging each
-- collection costs a pass over the whole store for a number usually zero.
SELECT b.collection, b.link_id, b.source, b.handle, b.conflict_revision,
       b.base_object, i.object_hash, b.conflict_object
FROM bindings b
JOIN items i ON i.collection = b.collection AND i.link_id = b.link_id
JOIN collections c ON c.id = b.collection
WHERE b.conflicted = 1 AND c.account IS :account
ORDER BY b.collection, b.link_id, b.source;

-- name: link_for_handle
-- A write batch dropping a placement names a handle, while the shared item is
-- keyed by link id. Rides bindings_by_handle, so it is a seek: answering it by
-- loading the collection is what makes a one-row write cost a whole-mailbox
-- read (§14).
SELECT link_id FROM bindings
WHERE collection = :collection AND source = :source AND handle = :handle;
