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
-- Requires SQLite >= 3.37 (STRICT tables, DROP COLUMN).

-- Store-level metadata: exactly one row.
CREATE TABLE store_meta (
    id         INTEGER PRIMARY KEY CHECK (id = 1),
    format     TEXT    NOT NULL DEFAULT 'pimdir',
    version    INTEGER NOT NULL,            -- store format version; tracks user_version
    hash_algo  TEXT    NOT NULL,            -- 'blake3' (default) or 'sha256-128'
    created_at TEXT    NOT NULL             -- RFC 3339 timestamp
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
    conflict    TEXT NOT NULL DEFAULT 'manual'
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
    link_id         TEXT NOT NULL,         -- cross-source identity (Message-ID / vCard-iCal UID)
    flags           TEXT,                  -- JSON array of flag strings (shared mutable state)
    object_hash     TEXT REFERENCES objects(hash),  -- current body; NULL until hydrated
    meta            TEXT,                  -- opaque summary (envelope); NULL until Meta-fetched
    level           INTEGER NOT NULL,      -- detail ladder: 0 probed, 1 meta, 2 full
    deleted         INTEGER NOT NULL DEFAULT 0,      -- 1 while a delete is propagating across sources
    conflicted      INTEGER NOT NULL DEFAULT 0,      -- 1 while a content conflict is unresolved
    conflict_object TEXT REFERENCES objects(hash),   -- the diverging body a Manual conflict recorded
    PRIMARY KEY (collection, link_id)
) STRICT;

-- One source's binding of an item: its handle there and the base last synced
-- with it (the three-way-merge baseline).
CREATE TABLE bindings (
    collection    TEXT NOT NULL,
    link_id       TEXT NOT NULL,
    source        TEXT NOT NULL,           -- which source this base belongs to
    handle        TEXT NOT NULL,           -- the item's backend id on this source (IMAP UID, DAV href)
    base_flags    TEXT,                    -- JSON array of strings, or NULL
    base_object   TEXT REFERENCES objects(hash),
    base_revision TEXT,                    -- etag/modseq for mutable-content backends
    PRIMARY KEY (collection, link_id, source),
    FOREIGN KEY (collection, link_id) REFERENCES items(collection, link_id) ON DELETE CASCADE
) STRICT;

-- Cross-source identity lookup (dedup, thread stitching) and refcount navigation.
CREATE INDEX items_by_object ON items(object_hash);
CREATE INDEX bindings_by_object ON bindings(base_object);
