-- pimdir store schema, version 1.
--
-- Applied by a migration runner (see SPEC.md §6) against an empty database,
-- inside a transaction; the runner sets `PRAGMA user_version = 1` on success.
-- Pure DDL: any implementation applies the identical bytes.
--
-- A store keeps one shared ITEM per logical thing (its truth: flags, body,
-- summary) and one BINDING per source that syncs it (that source's last-agreed
-- base). A single-source store is the degenerate case of one binding per item;
-- a two-source store (two servers, or a server and a phone) keeps two.
--
-- The store has a single writing owner (SPEC.md §8). The QUEUE is how every
-- other process mutates anyway: a producer appends an action row (with, at
-- most, the object upsert pinning its body), and the owner applies pending
-- actions to the items and bindings, deleting each in the same transaction as
-- its effects, so an action is applied exactly once. Payloads are versioned
-- JSON per action kind, and kinds are extensible: an owner that cannot apply a
-- kind skips the row, leaving it pending for one that can (SPEC.md §15).
--
-- Requires SQLite >= 3.37 (STRICT tables, DROP COLUMN).

-- Store-level metadata: exactly one row.
CREATE TABLE store_meta (
    id         INTEGER PRIMARY KEY CHECK (id = 1),
    format     TEXT    NOT NULL DEFAULT 'pimdir',
    version    INTEGER NOT NULL,            -- store format version; tracks user_version
    hash_algo  TEXT    NOT NULL,            -- 'blake3' (default) or 'sha256-128'
    created_at TEXT    NOT NULL,            -- RFC 3339 timestamp
    -- Store-global monotonic counter handing out the next item `seq`. Only ever
    -- increases, so a public id is never reused across the whole store.
    next_seq   INTEGER NOT NULL DEFAULT 1
) STRICT;

-- Collections: mailboxes, address books, calendars. Hierarchy is by `parent`,
-- never by nesting rows.
--
-- `account` is the multi-account axis (SPEC.md §9.2): NULL in a single-account
-- store, an opaque owner-chosen id when one store holds several. It groups; it
-- neither keys nor partitions. `id` stays unique store-wide, so an owner filing
-- two accounts here namespaces their collection ids (`work/INBOX`,
-- `home/INBOX`) and records the grouping in this column rather than leaving
-- readers to parse it back out of the id.
--
-- No identifier is scoped by it: an identity or a body occurring in two
-- accounts is a fact the store reports (list_link_placements,
-- list_object_placements) and an interface interprets. Mail lists the
-- placements, contacts may merge them; the store decides neither.
CREATE TABLE collections (
    id          TEXT PRIMARY KEY,          -- stable id (base32 uuid or backend id), unique store-wide
    account     TEXT,                      -- owning account id, or NULL in a single-account store
    kind        TEXT NOT NULL,             -- media type: message/rfc822, text/vcard, text/calendar, text/plain
    name        TEXT NOT NULL,             -- logical name (INBOX, Contacts)
    parent      TEXT REFERENCES collections(id) ON UPDATE CASCADE ON DELETE SET NULL,
    color       TEXT,                      -- optional presentation
    description TEXT,
    sort_order  INTEGER,
    -- Cross-source content-conflict policy: 'manual' | 'prefer-incoming' | 'prefer-existing'.
    conflict    TEXT NOT NULL DEFAULT 'manual',
    -- Collection generation: bumped by the owner whenever it rebuilds the
    -- collection's handle space (a backend identity reset), so a reader can derive
    -- epoch-dependent protocol values (an IMAP UIDVALIDITY) from the store alone
    -- (SPEC.md §12).
    generation  INTEGER NOT NULL DEFAULT 1
) STRICT;

-- "Every collection of this account", the merged view's filter axis and the
-- scope of the seq lookup below. Partial: a single-account store writes no
-- account and pays for no index.
CREATE INDEX collections_by_account ON collections(account) WHERE account IS NOT NULL;

-- One row per source that syncs a collection (a server, a phone). A
-- single-source collection has one row here; the sync cursor is per source.
CREATE TABLE sources (
    collection TEXT NOT NULL REFERENCES collections(id) ON UPDATE CASCADE ON DELETE CASCADE,
    source     TEXT NOT NULL,              -- source id (e.g. 'left', 'right', 'phone')
    checkpoint BLOB,                        -- opaque remote sync cursor (QRESYNC/JMAP state, DAV sync-token)
    PRIMARY KEY (collection, source)
) STRICT;

-- Objects: content-addressed item bodies. The BYTES live in blob files at
-- objects/<hash> (SPEC.md §5); this table is the index + refcount.
CREATE TABLE objects (
    hash     TEXT PRIMARY KEY,             -- content hash under store_meta.hash_algo, base32
    size     INTEGER NOT NULL,             -- body length in bytes
    refcount INTEGER NOT NULL DEFAULT 0    -- placements/bindings referencing it (live, base or conflict)
) STRICT;

-- The shared truth of one logical item, keyed by its cross-source link id.
-- `deleted` lingers after one source removes it, until every source has dropped
-- it too — the cross-source delete memory that a single-source store never needs.
-- Once the last source has dropped it, the row is RETAINED rather than deleted
-- (`retained_at` non-NULL): it keeps its object_hash, so the body stays pinned
-- and its blob survives GC, and only an explicit purge removes it (SPEC.md §11).
CREATE TABLE items (
    collection      TEXT NOT NULL REFERENCES collections(id) ON UPDATE CASCADE ON DELETE CASCADE,
    link_id         TEXT NOT NULL,         -- cross-source identity (Message-ID / vCard-iCal UID), internal
    seq             INTEGER NOT NULL,      -- the message's public id: store-global, one per link_id (shared across its mailboxes and accounts), never reused
    flags           TEXT,                  -- JSON array of flag strings (shared mutable state)
    object_hash     TEXT REFERENCES objects(hash),  -- current body; NULL until hydrated
    meta            TEXT,                  -- opaque summary (envelope); NULL until Meta-fetched
    sort_key        TEXT NOT NULL DEFAULT '',  -- the kind's ordering key, written beside meta; '' means unknown
    level           INTEGER NOT NULL,      -- detail ladder: 0 probed, 1 meta, 2 full
    deleted         INTEGER NOT NULL DEFAULT 0,      -- 1 while a delete is propagating across sources
    retained_at     TEXT,    -- RFC 3339 instant the last binding vanished; non-NULL means retained (soft-deleted)
    retained_by     TEXT,    -- the source whose removal retired the item, diagnostic only
    conflicted      INTEGER NOT NULL DEFAULT 0,      -- 1 while a content conflict is unresolved
    conflict_object TEXT REFERENCES objects(hash),   -- the diverging body a Manual conflict recorded
    PRIMARY KEY (collection, link_id)
) STRICT;

-- A message's public id is shared by its placements, so it is unique per
-- (collection, seq); a client resolves it back to the internal `link_id`.
CREATE UNIQUE INDEX items_by_seq ON items(collection, seq);
-- The same link id can occur in several collections (a message filed in two
-- mailboxes); this indexes the "does this message already have a seq?" lookup that
-- makes all its placements share one id. Also services list_link_placements,
-- the read that reports every collection and account an identity occurs in
-- (SPEC.md §9.2).
CREATE INDEX items_by_link ON items(link_id);
-- Retained (soft-deleted) items: the purge sweep and the trash listing scan only these.
CREATE INDEX items_retained ON items(collection, retained_at) WHERE retained_at IS NOT NULL;
-- Orders a collection by the kind's own sort key, with `seq` as the tiebreaker
-- that makes a keyset page over a non-unique key well defined. Without this the
-- only orderings a store can serve are by `link_id` (the primary key) or by
-- `seq`, neither of which means anything to a reader: a mail client cannot ask
-- for the newest messages and a calendar cannot ask for a date range.
CREATE INDEX items_by_sort ON items(collection, sort_key, seq);
-- `seq` is the store-global public id (SPEC.md §9.1): a consumer displays it
-- and accepts it back, without naming the collection it came from. Resolving one
-- against items_by_seq above means scanning that whole index, since it leads
-- with the collection, so the store-global read the spec promises needs a
-- store-global index.
CREATE INDEX items_by_seq_global ON items(seq);

-- One source's binding of an item: its handle there, the base last synced with
-- it (the three-way-merge baseline), and whether that source's own sync is
-- stuck on an unresolved content conflict.
CREATE TABLE bindings (
    collection        TEXT NOT NULL,
    link_id           TEXT NOT NULL,
    source            TEXT NOT NULL,       -- which source this base belongs to
    handle            TEXT NOT NULL,       -- the item's backend id on this source (IMAP UID, DAV href)
    base_flags        TEXT,                -- JSON array of strings, or NULL
    base_object       TEXT REFERENCES objects(hash),
    base_revision     TEXT,                -- etag/modseq for mutable-content backends
    -- Whether a base exists at all, which its three value columns cannot say:
    -- a source reporting no revision, no body and markers nobody has read still
    -- agreed, and that agreement is what tells a pending push from a settled
    -- one. Inferring presence from the three loses exactly that shape, and the
    -- placement then reads as never-agreed for ever (SPEC.md §13).
    base_present      INTEGER NOT NULL DEFAULT 0,
    -- This source and its OWN remote diverged (§10). Distinct from
    -- items.conflicted, which is the cross-source divergence.
    conflicted        INTEGER NOT NULL DEFAULT 0,
    conflict_revision TEXT,                -- the remote revision observed when it did, or NULL
    -- The OTHER handles this source holds this identity under, as a JSON array,
    -- or NULL. The identity-axis twin of `conflicted`: a source may hold one
    -- link id twice (a double delivery, a retried APPEND, a restore, a
    -- migration), and a binding pins one handle, so the second has nowhere to
    -- live. Recording it here is what keeps the write from silently repointing
    -- the binding and destroying the evidence, and what makes the resulting
    -- freeze survive a restart: the second copy appears in exactly one
    -- enumeration, and an incremental one never mentions it again (SPEC.md §10).
    ambiguous_handles TEXT,
    PRIMARY KEY (collection, link_id, source),
    -- ON UPDATE CASCADE as well as ON DELETE: renaming a collection cascades
    -- into items.collection, which is this composite key's parent, so without it
    -- the rename is refused one level down (SPEC.md §14).
    FOREIGN KEY (collection, link_id) REFERENCES items(collection, link_id) ON UPDATE CASCADE ON DELETE CASCADE
) STRICT;

-- The action queue (SPEC.md §15): mutations requested by processes that are not
-- the store owner, applied by the owner in append order.
CREATE TABLE queue (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,  -- global append order
    created_at  TEXT    NOT NULL,                   -- RFC 3339 timestamp
    producer    TEXT    NOT NULL,                   -- enqueuing process, diagnostic only
    collection  TEXT    NOT NULL REFERENCES collections(id) ON UPDATE CASCADE ON DELETE CASCADE,
    action      TEXT    NOT NULL,                   -- 'add' | 'set-flags' | 'remove' | 'move' | 'copy' | 'update' | app-defined (SPEC.md §15.3)
    payload     TEXT    NOT NULL,                   -- versioned JSON, shape per action (SPEC.md §15)
    object_hash TEXT    REFERENCES objects(hash),   -- pins the payload's body against GC, or NULL
    attempts    INTEGER NOT NULL DEFAULT 0,         -- apply attempts so far
    error       TEXT                                -- last failure; non-NULL means parked
) STRICT;

-- The owner drains a collection's pending actions in append order.
CREATE INDEX queue_by_collection ON queue(collection, id);

-- Cross-source identity lookup (dedup, thread stitching) and refcount navigation.
CREATE INDEX items_by_object ON items(object_hash);
CREATE INDEX bindings_by_object ON bindings(base_object);
-- The sweep of unreferenced objects (SPEC.md §5, §14). Partial, so it holds only
-- what is about to be collected and is empty at rest: without it both the list
-- and the delete scan the whole objects table, on every write transaction.
CREATE INDEX objects_garbage ON objects(refcount) WHERE refcount <= 0;
-- The other two pointers at an object, so recompute_refcounts (queries/objects.sql)
-- can reach every reference by index rather than by scanning items and queue once
-- per object row.
CREATE INDEX items_by_conflict_object ON items(conflict_object);
CREATE INDEX queue_by_object ON queue(object_hash);
-- Resolves one source handle back to the link id it is bound to (link_for_handle,
-- queries/bindings.sql), which is what a batch dropping a placement needs: a drop
-- names a handle and the shared item is keyed by link id. Without it, folding a
-- drop into the hub means scanning every item of the collection.
CREATE INDEX bindings_by_handle ON bindings(collection, source, handle);
