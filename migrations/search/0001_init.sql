-- pimdir search index schema, version 1. Section references are to SEARCH.md.
--
-- Applied to index.db, beside pimdir.db, by the same runner shape (§3), the
-- index's own `PRAGMA user_version` set to 1 on success. Derived state: a
-- mismatch is a rebuild, never a migration. Requires SQLite >= 3.43 for
-- contentless_delete, above the store's floor (§2).

-- Index-level metadata: exactly one row.
CREATE TABLE index_meta (
    id            INTEGER PRIMARY KEY CHECK (id = 1),
    format        TEXT    NOT NULL DEFAULT 'pimdir-index',
    version       INTEGER NOT NULL,           -- tracks user_version
    tokenizer     TEXT    NOT NULL,           -- the FTS5 tokenize string in force (§5)
    -- The store's change cursor this index has folded in (§4): every stamp up
    -- to and including store_change, the last one drawn when the pass began,
    -- at purge count store_purges.
    store_change  INTEGER NOT NULL DEFAULT 0,
    store_purges  INTEGER NOT NULL DEFAULT 0,
    -- The window occurrences are expanded within (§7), RFC 3339 Z.
    horizon_start TEXT    NOT NULL DEFAULT '',
    horizon_end   TEXT    NOT NULL DEFAULT ''
) STRICT;

-- One row per indexed body, keyed on the store's object hash. The input is
-- immutable, so a row is never re-indexed; it goes when the object goes.
--
-- `id` is an explicit INTEGER PRIMARY KEY, so it is the rowid and stable: a
-- table keyed on anything else has an implicit rowid VACUUM may renumber, and
-- the FTS rows below are joined on it.
CREATE TABLE object (
    id     INTEGER PRIMARY KEY,
    hash   TEXT    NOT NULL UNIQUE,
    status TEXT    NOT NULL                  -- 'ok' | 'encrypted' | 'unparseable' (§6)
) STRICT;

-- The text of a body, by field (§6): the seven fields, then one column per
-- address role of Annex A.6 so `from:` and `to:` keep their role where the
-- value is a name rather than an address. Contentless: the bytes stay in the
-- blob, and a snippet is re-read from it. rowid = object.id.
CREATE VIRTUAL TABLE object_text USING fts5(
    title, people, body, attachment, place, org, note,
    "from", "to", cc, bcc, email, organizer, attendee,
    content = '', contentless_delete = 1,
    tokenize = 'unicode61 remove_diacritics 2', prefix = '2 3'
);

-- The placements the index knows, so a purge or a rename is reconciled by key
-- (§4) and a mutable item's new body is found (§6). `id` is the stable rowid
-- summary_text joins on, for the reason object.id gives.
CREATE TABLE placement (
    id         INTEGER PRIMARY KEY,
    collection TEXT    NOT NULL,
    seq        INTEGER NOT NULL,
    link_id    TEXT    NOT NULL,
    hash       TEXT,                         -- the body indexed for it, or NULL while bodiless
    UNIQUE (collection, seq)
) STRICT;

CREATE INDEX placement_by_hash ON placement(hash);
CREATE INDEX placement_by_link ON placement(link_id);

-- The summary of a bodiless placement (§6), so a headers-only replica still
-- searches; dropped when the body arrives. rowid = placement.id.
CREATE VIRTUAL TABLE summary_text USING fts5(
    title, people, "from", "to", cc, bcc, email, organizer, attendee,
    content = '', contentless_delete = 1,
    tokenize = 'unicode61 remove_diacritics 2', prefix = '2 3'
);

-- The flag predicates (§8), one row per flag per placement, so `is:unread`
-- alone is a seek rather than a JSON scan of every item. Cascades with the
-- placement, so a dropped placement takes its flags with it (§4).
CREATE TABLE flag (
    flag       TEXT    NOT NULL,
    collection TEXT    NOT NULL,
    seq        INTEGER NOT NULL,
    PRIMARY KEY (flag, collection, seq),
    FOREIGN KEY (collection, seq) REFERENCES placement(collection, seq) ON DELETE CASCADE
) STRICT;

CREATE INDEX flag_by_placement ON flag(collection, seq);

-- Calendar time (§7): every occurrence within the horizon, so a date predicate
-- reaches a recurring series where items.sort_key holds only its first start.
-- Cascades with the placement like flag.
CREATE TABLE occurrence (
    collection TEXT    NOT NULL,
    seq        INTEGER NOT NULL,
    start      TEXT    NOT NULL,             -- RFC 3339 Z
    end        TEXT    NOT NULL,
    FOREIGN KEY (collection, seq) REFERENCES placement(collection, seq) ON DELETE CASCADE
) STRICT;

CREATE INDEX occurrence_by_start ON occurrence(start, end);
CREATE INDEX occurrence_by_item ON occurrence(collection, seq);

-- Mail threads (§9), keyed on message ids so a message in three mailboxes is
-- one node. A message row exists for every id a member names, present in the
-- store or not, so two replies to a parent the store never held still join;
-- thread_members reaches the present ones through placement.
CREATE TABLE thread (
    id    TEXT    PRIMARY KEY,
    first TEXT    NOT NULL,                  -- earliest sort key in the thread
    last  TEXT    NOT NULL,                  -- latest
    count INTEGER NOT NULL                   -- present members
) STRICT;

CREATE TABLE message (
    link_id TEXT PRIMARY KEY,
    thread  TEXT NOT NULL REFERENCES thread(id) ON DELETE CASCADE,
    parent  TEXT                             -- the message id replied to, or NULL
) STRICT;

CREATE INDEX message_by_thread ON message(thread);
-- A parent arriving after its children finds them by a seek, not a scan.
CREATE INDEX message_by_parent ON message(parent);
