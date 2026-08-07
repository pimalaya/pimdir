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
-- The store has a single writing owner (SPEC.md §7). The QUEUE is how every
-- other process mutates anyway: a producer appends an action row (with, at
-- most, the object upsert pinning its body), and the owner applies pending
-- actions to the items and bindings, deleting each in the same transaction as
-- its effects, so an action is applied exactly once. Payloads are versioned
-- JSON per action kind (SPEC.md §14).
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
CREATE TABLE collections (
    id          TEXT PRIMARY KEY,          -- stable id (base32 uuid or backend id)
    kind        TEXT NOT NULL,             -- media type: message/rfc822, text/vcard, text/calendar, text/plain
    name        TEXT NOT NULL,             -- logical name (INBOX, Contacts)
    parent      TEXT REFERENCES collections(id) ON DELETE SET NULL,
    color       TEXT,                      -- optional presentation
    description TEXT,
    sort_order  INTEGER,
    -- Cross-source content-conflict policy: 'manual' | 'prefer-incoming' | 'prefer-existing'.
    conflict    TEXT NOT NULL DEFAULT 'manual',
    -- Collection generation: bumped by the owner whenever it rebuilds the
    -- collection's handle space (a backend identity reset), so a reader can derive
    -- epoch-dependent protocol values (an IMAP UIDVALIDITY) from the store alone
    -- (SPEC.md §15).
    generation  INTEGER NOT NULL DEFAULT 1
) STRICT;

-- One row per source that syncs a collection (a server, a phone). A
-- single-source collection has one row here; the sync cursor is per source.
CREATE TABLE sources (
    collection TEXT NOT NULL REFERENCES collections(id) ON DELETE CASCADE,
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
CREATE TABLE items (
    collection      TEXT NOT NULL REFERENCES collections(id) ON DELETE CASCADE,
    link_id         TEXT NOT NULL,         -- cross-source identity (Message-ID / vCard-iCal UID), internal
    seq             INTEGER NOT NULL,      -- the message's public id: store-global, one per link_id (shared across its mailboxes), never reused
    flags           TEXT,                  -- JSON array of flag strings (shared mutable state)
    object_hash     TEXT REFERENCES objects(hash),  -- current body; NULL until hydrated
    meta            TEXT,                  -- opaque summary (envelope); NULL until Meta-fetched
    level           INTEGER NOT NULL,      -- detail ladder: 0 probed, 1 meta, 2 full
    deleted         INTEGER NOT NULL DEFAULT 0,      -- 1 while a delete is propagating across sources
    conflicted      INTEGER NOT NULL DEFAULT 0,      -- 1 while a content conflict is unresolved
    conflict_object TEXT REFERENCES objects(hash),   -- the diverging body a Manual conflict recorded
    PRIMARY KEY (collection, link_id)
) STRICT;

-- A message's public id is shared by its placements, so it is unique per
-- (collection, seq); a client resolves it back to the internal `link_id`.
CREATE UNIQUE INDEX items_by_seq ON items(collection, seq);
-- The same link id can occur in several collections (a message filed in two
-- mailboxes); this indexes the "does this message already have a seq?" lookup that
-- makes all its placements share one id.
CREATE INDEX items_by_link ON items(link_id);

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
    -- This source and its OWN remote diverged (§10). Distinct from
    -- items.conflicted, which is the cross-source divergence.
    conflicted        INTEGER NOT NULL DEFAULT 0,
    conflict_revision TEXT,                -- the remote revision observed when it did, or NULL
    PRIMARY KEY (collection, link_id, source),
    FOREIGN KEY (collection, link_id) REFERENCES items(collection, link_id) ON DELETE CASCADE
) STRICT;

-- The action queue (SPEC.md §14): mutations requested by processes that are not
-- the store owner, applied by the owner in append order.
CREATE TABLE queue (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,  -- global append order
    created_at  TEXT    NOT NULL,                   -- RFC 3339 timestamp
    producer    TEXT    NOT NULL,                   -- enqueuing process, diagnostic only
    collection  TEXT    NOT NULL REFERENCES collections(id) ON DELETE CASCADE,
    action      TEXT    NOT NULL,                   -- 'add' | 'set-flags' | 'remove' | 'move' | 'copy' | 'update'
    payload     TEXT    NOT NULL,                   -- versioned JSON, shape per action (SPEC.md §14)
    object_hash TEXT    REFERENCES objects(hash),   -- pins the payload's body against GC, or NULL
    attempts    INTEGER NOT NULL DEFAULT 0,         -- apply attempts so far
    error       TEXT                                -- last failure; non-NULL means parked
) STRICT;

-- The owner drains a collection's pending actions in append order.
CREATE INDEX queue_by_collection ON queue(collection, id);

-- Cross-source identity lookup (dedup, thread stitching) and refcount navigation.
CREATE INDEX items_by_object ON items(object_hash);
CREATE INDEX bindings_by_object ON bindings(base_object);
