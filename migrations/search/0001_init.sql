-- pimdir search index schema, version 1. Section references are to SEARCH.md.
--
-- Applied to index.db, beside pimdir.db, in one transaction, the
-- index's own `PRAGMA user_version` set to 1 on success. Derived state: an
-- older version of this shape, or a mismatch of the tokenizer, the schema text
-- or the store (§2), is a rebuild, never a migration. The canonical shape
-- (§2): needs SQLite >= 3.43 with FTS5 for contentless_delete, above the
-- store's.

-- Index-level metadata: exactly one row.
CREATE TABLE index_meta (
    id            INTEGER PRIMARY KEY CHECK (id = 1),
    format        TEXT    NOT NULL DEFAULT 'pimdir-index',
    -- The version of SEARCH.md this index follows and the shape it is written
    -- in (§2): the draft's own name while SEARCH.md is a draft, search-vN once
    -- released; 'canonical' for this schema. Every shape records both, so an
    -- indexer rebuilds only an older index of its own shape and refuses any
    -- other, and a query client refuses one it does not implement.
    format_version TEXT   NOT NULL,
    shape         TEXT    NOT NULL,
    version       INTEGER NOT NULL,           -- tracks user_version
    tokenizer     TEXT    NOT NULL,           -- the FTS5 tokenize string in force (§5)
    -- The store this index was built from (§2, §4): its store_meta.store_id and
    -- incarnation when init_index_meta ran. A store answering another is a
    -- restored copy or another store, and the index is rebuilt.
    store_id          TEXT    NOT NULL,
    store_incarnation INTEGER NOT NULL,
    -- The store's change cursor this index has folded in (§4): every stamp up
    -- to and including store_change, the last one drawn when the pass began,
    -- at purge count store_purges, which a batch never moves, so a rename a
    -- cut pass folded past is still reconciled.
    store_change  INTEGER NOT NULL DEFAULT 0,
    store_purges  INTEGER NOT NULL DEFAULT 0,
    -- The window occurrences are expanded within (§7), RFC 3339 Z.
    horizon_start TEXT    NOT NULL DEFAULT '',
    horizon_end   TEXT    NOT NULL DEFAULT '',
    -- The time zone database version the occurrences were expanded under (§7),
    -- as the database names its release (IANA's `2026b`), '' with none: another
    -- version re-expands the calendar items.
    tzdb_version  TEXT    NOT NULL DEFAULT '',
    -- The time zone floating times and dates were read in (§7), an IANA name or
    -- UTC: an indexer stating another re-expands the calendar items.
    floating_zone TEXT    NOT NULL DEFAULT 'UTC',
    -- The revision of §6 the bodies were extracted and the occurrences
    -- expanded under, and the indexer's own for what §6 leaves to it, an
    -- opaque text (§2): an indexer at another of either extracts every held
    -- body again and records its own.
    extraction    INTEGER NOT NULL,
    extractor     TEXT    NOT NULL
) STRICT;

-- One row per indexed body, named by the store's object hash, a name of
-- STORAGE.md §5 by the same CHECK as the store's, which the indexer finds the
-- body's blob by. The input is immutable, so a row is written once under a
-- revision of the extraction (§2); it goes when the object goes.
--
-- `id` is the body's key in the index, the one every row naming the body
-- carries (§3): an explicit INTEGER PRIMARY KEY, so it is the rowid and
-- stable, a table keyed on anything else having an implicit rowid VACUUM may
-- renumber, and the FTS rows below are joined on it. Drawn above every id
-- drawn before (AUTOINCREMENT), so a new body's rows land at the end of every
-- index on it, and never reused, so a placement still naming a body the pass
-- deleted never comes to name another.
CREATE TABLE object (
    id     INTEGER PRIMARY KEY AUTOINCREMENT,
    hash   TEXT    NOT NULL UNIQUE CHECK (length(hash) = 52 AND hash NOT GLOB '*[^a-z2-7]*'),
    status TEXT    NOT NULL,                 -- 'ok' | 'encrypted' | 'unparseable' (§6)
    -- 1 when the extraction wrote any text into the attachment field (§6),
    -- so has:attachment reads a calendar item by a seek, the FTS rows keeping
    -- none.
    attachment INTEGER NOT NULL CHECK (attachment IN (0, 1)),
    -- 1 when a card holds a TEL, an ADR, a BDAY, a PHOTO (§6), so has:phone,
    -- has:address, has:birthday and has:photo read it by a seek; 0 for any
    -- other kind.
    tel    INTEGER NOT NULL CHECK (tel IN (0, 1)),
    adr    INTEGER NOT NULL CHECK (adr IN (0, 1)),
    bday   INTEGER NOT NULL CHECK (bday IN (0, 1)),
    photo  INTEGER NOT NULL CHECK (photo IN (0, 1))
) STRICT;

-- The bodies the extraction did not read whole (§6), encrypted or
-- unparseable, so a query's coverage counts them by a seek (coverage, §8.2).
-- Partial, so it holds those few alone.
CREATE INDEX object_not_ok ON object(status) WHERE status <> 'ok';

-- A card's CATEGORIES values (§6), folded, each once, so category: reads a
-- card by a seek as it reads a task on the store's task_summary. Gone with
-- the object.
CREATE TABLE object_category (
    object INTEGER NOT NULL REFERENCES object(id) ON DELETE CASCADE,
    value  TEXT    NOT NULL,
    PRIMARY KEY (object, value)
) STRICT;

CREATE INDEX object_category_by_value ON object_category(value);

-- The text of a body, by field (§6): the seven fields, then one column per
-- address role of Annex A.6 so `from:` and `to:` keep their role where the
-- value is a name rather than an address. Contentless: the bytes stay in the
-- blob, and a snippet is re-read from it. rowid = object.id. The text arrives
-- folded (§5), so the tokenizer folds no diacritic of its own.
CREATE VIRTUAL TABLE object_text USING fts5(
    title, people, body, attachment, place, org, note,
    "from", "to", cc, bcc, email, organizer, attendee,
    content = '', contentless_delete = 1,
    tokenize = 'unicode61 remove_diacritics 0', prefix = '2 3'
);

-- The chunk boundaries of a body's long fields (§6), so a snippet is cut from
-- them and an embedding index embeds the same chunks without extracting again.
-- Only `body` and `note` are chunked. Offsets are UTF-8 bytes into the field's
-- extracted text, which stays in the blob; the rows go with the object.
CREATE TABLE chunk (
    object INTEGER NOT NULL REFERENCES object(id) ON DELETE CASCADE,
    ord    INTEGER NOT NULL,           -- 0-based, in text order across fields
    field  TEXT    NOT NULL,           -- 'body' | 'note'
    start  INTEGER NOT NULL,           -- UTF-8 byte offset into the text
    end    INTEGER NOT NULL,           -- exclusive
    PRIMARY KEY (object, ord)
) STRICT;

-- The placements the index knows, so a purge or a rename is reconciled by key
-- (§4) and a mutable item's new body is found (§6). `id` is the stable rowid
-- summary_text joins on, for the reason object.id gives.
CREATE TABLE placement (
    id         INTEGER PRIMARY KEY,
    collection TEXT    NOT NULL,
    seq        INTEGER NOT NULL,
    link_id    TEXT    NOT NULL,
    -- The body indexed for it, its object.id, or NULL while bodiless or
    -- while its body was never read (§4). No foreign key: a pass deleting a
    -- body the collector took (objects_gone) may come before the one moving a
    -- placement off it, and the id names no other body meanwhile. A hash the
    -- index does not hold resolves to 0 (upsert_placement), which the CHECK
    -- refuses, so naming a body never indexed fails rather than writing none.
    object     INTEGER CHECK (object > 0),
    -- The instant from which a calendar item's occurrences are not all
    -- written, RFC 3339 Z, when §7's bounds stopped its expansion; NULL
    -- otherwise.
    cut        TEXT,
    UNIQUE (collection, seq)
) STRICT;

-- The placements of a body, which every join from a body to its placements
-- seeks (§3), and object_placed. Partial on the pointer being set, as the
-- store's pointer indexes are (STORAGE.md §4.3): an equality implies it.
CREATE INDEX placement_by_object ON placement(object) WHERE object IS NOT NULL;
CREATE INDEX placement_by_link ON placement(link_id);
-- The items a query's coverage reports cut (cut_before, §8.2), by
-- collection. Partial, so it holds the few cut items alone.
CREATE INDEX placement_cut ON placement(collection, cut) WHERE cut IS NOT NULL;
-- The placements of a public id, which split_mark counts the documents of.
CREATE INDEX placement_by_seq ON placement(seq);

-- The public ids whose placements name two or more documents (§3): a
-- document is a placement's body, or its own summary while it has none,
-- the two told apart by coalesce(object, -id), so two placements naming one
-- body name one document and two bodiless ones name two. A text term holds
-- for a hit when any of its placements matches it (§8.2): a hit naming one
-- document matches a whole expression exactly when that document does, and
-- a count may match one, but a hit listed here is evaluated per placement.
-- Kept by split_forget and split_mark after each batch's placement writes
-- (§4).
CREATE TABLE split (
    seq INTEGER PRIMARY KEY
) STRICT;

-- The placements whose body the indexer could not read (§4): gone from the
-- blob directory or failing its name, when a pass went to index it or to
-- expand it again. Each pass reads them again, whether or not the store
-- stamps them again; a row goes once its body was read for what the pass
-- needed of it, and with its placement.
CREATE TABLE missing (
    collection TEXT    NOT NULL,
    seq        INTEGER NOT NULL,
    PRIMARY KEY (collection, seq),
    FOREIGN KEY (collection, seq) REFERENCES placement(collection, seq) ON DELETE CASCADE
) STRICT;

-- The summary of a bodiless placement (§6), so a headers-only replica still
-- searches; dropped when the body arrives. rowid = placement.id.
CREATE VIRTUAL TABLE summary_text USING fts5(
    title, people, "from", "to", cc, bcc, email, organizer, attendee,
    content = '', contentless_delete = 1,
    tokenize = 'unicode61 remove_diacritics 0', prefix = '2 3'
);

-- The keyword predicates (§8, §10), one row per keyword per placement, so
-- tag:x is a seek. A system flag is no row: `is:` and a tag: naming one read
-- the store's items.marks as it stands, so the CHECK refuses the five, each by
-- its exact bytes (STORAGE §13). Cascades with the placement, so a dropped
-- placement takes its keywords with it (§4).
CREATE TABLE flag (
    flag       TEXT    NOT NULL CHECK (flag NOT IN ('\Seen', '\Answered', '\Flagged', '\Draft', '\Deleted')),
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
-- one node. A message row exists for every id a held message bears or names,
-- and for no other, so two replies to a parent the store never held still
-- join and a purged message leaves nothing it named; thread_members reaches
-- the present ones through placement.
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
