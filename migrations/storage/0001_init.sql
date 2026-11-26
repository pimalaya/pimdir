-- pimdir store schema, version 1. Section references are to STORAGE.md.
--
-- Applied by a migration runner (§6) to a fresh database, inside a
-- transaction; the runner sets `PRAGMA user_version = 1` on success. Loads on
-- SQLite >= 3.18 (§4.1): a column's type is held by a CHECK on typeof() rather
-- than by STRICT, and nothing here calls a JSON function. This file is
-- version 1's and never changes: a change to the schema is a migration to the
-- next version (§6).

-- Pages freed by a delete go back to the filesystem when the owner asks
-- (§4.1). A database takes the mode only while it holds no table, so it is
-- set first.
PRAGMA auto_vacuum = INCREMENTAL;

-- Store-level metadata: exactly one row.
CREATE TABLE store_meta (
    id              INTEGER PRIMARY KEY CHECK (id = 1),
    format          TEXT    NOT NULL DEFAULT 'pimdir' CHECK (typeof(format) = 'text'),
    -- The version of STORAGE.md whose schema the store holds (§4.2),
    -- storage-vN, N its major alone. A draft's store, which named its draft,
    -- is refused.
    format_version  TEXT    NOT NULL CHECK (typeof(format_version) = 'text'),
    version         INTEGER NOT NULL CHECK (typeof(version) = 'integer'),  -- tracks user_version (§4.2)
    -- The lowest schema version a reader, and a producer, must know to open
    -- the store (§4.2), raised by a migration changing what they read or write
    -- (§6).
    read_version    INTEGER NOT NULL CHECK (typeof(read_version) = 'integer'),
    produce_version INTEGER NOT NULL CHECK (typeof(produce_version) = 'integer'),
    -- Which store this is and which copy of it (§4.5, §8): 32 lowercase hex
    -- digits drawn at creation and never changed, and 1 at creation, raised by
    -- every restore, so a consumer never takes a restored copy for the store
    -- it followed.
    store_id        TEXT    NOT NULL CHECK (typeof(store_id) = 'text')
                    CHECK (length(store_id) = 32 AND store_id NOT GLOB '*[^0-9a-f]*'),
    incarnation     INTEGER NOT NULL CHECK (typeof(incarnation) = 'integer') CHECK (incarnation >= 1),
    -- The content hash naming every body (§5): BLAKE3 alone, a closed
    -- vocabulary (§13), so another algorithm is a value a migration adds,
    -- raising read_version (§6), and never a store a program reads as corrupt.
    hash_algo       TEXT    NOT NULL CHECK (typeof(hash_algo) = 'text') CHECK (hash_algo IN ('blake3')),
    created_at      TEXT    NOT NULL CHECK (typeof(created_at) = 'text')  -- stamped by SQLite, the shape of §13
                    CHECK (created_at GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9].[0-9][0-9][0-9]Z'),
    -- The Annex A revision the summaries were derived under (§6): an owner at
    -- a later one re-derives what changed, then records it; one at an earlier
    -- one writing summaries records its own, so the next later owner
    -- re-derives them.
    derivation      INTEGER NOT NULL CHECK (typeof(derivation) = 'integer'),
    -- The version of SYNC.md whose engine wrote the sync state (§14): NULL
    -- until an engine writes, then its own, sync-vN. An engine refuses a
    -- version it does not implement (SYNC.md §10).
    sync_version    TEXT    CHECK (typeof(sync_version) IN ('text', 'null')),
    -- Hands out the next item `seq`; only ever increases, so a public id is
    -- never reused store-wide (§9.1).
    next_seq        INTEGER NOT NULL DEFAULT 1 CHECK (typeof(next_seq) = 'integer'),
    -- The next change stamp (§4.5), drawn by the triggers below; a consumer
    -- records next_change - 1, the last stamp drawn.
    next_change     INTEGER NOT NULL DEFAULT 1 CHECK (typeof(next_change) = 'integer'),
    -- Rows that left without a stamp and renamed collections (§4.5): purged
    -- items, collected objects and deleted collections, counted by the delete
    -- triggers below, and every rename, counted by collections_restamp_items.
    purges          INTEGER NOT NULL DEFAULT 0 CHECK (typeof(purges) = 'integer')
);

-- The store's id never changes and its incarnation never goes down (§8): a
-- consumer comparing the two then never takes one store, or an older copy,
-- for another.
CREATE TRIGGER store_meta_identity BEFORE UPDATE OF store_id, incarnation ON store_meta
WHEN NEW.store_id IS NOT OLD.store_id OR NEW.incarnation < OLD.incarnation
BEGIN
    SELECT RAISE(ABORT, 'store identity is fixed');
END;

-- Collections: mailboxes, address books, calendars. Hierarchy is by `parent`,
-- never by nesting rows.
--
-- `account` groups collections and partitions no identifier (§9.2). `id` stays
-- unique store-wide, so an owner holding two accounts namespaces their ids
-- itself (`work/INBOX`, `home/INBOX`) and records the grouping in this column
-- rather than leaving readers to parse it back out.
CREATE TABLE collections (
    id          TEXT PRIMARY KEY CHECK (typeof(id) = 'text') CHECK (id != ''),  -- stable id (base32 uuid or backend id), unique store-wide, never empty
    account     TEXT CHECK (typeof(account) IN ('text', 'null')) CHECK (account != ''),  -- owning account, NULL in a single-account store, never empty
    -- The media type every item shares, a closed set (§13), '' until declared.
    kind        TEXT NOT NULL CHECK (typeof(kind) = 'text') CHECK (kind IN ('', 'message/rfc822', 'text/vcard', 'text/calendar',
                'application/octet-stream')),
    name        TEXT NOT NULL CHECK (typeof(name) = 'text'),  -- logical name (INBOX, Contacts)
    parent      TEXT CHECK (typeof(parent) IN ('text', 'null')) REFERENCES collections(id) ON UPDATE CASCADE ON DELETE SET NULL,
    color       TEXT CHECK (typeof(color) IN ('text', 'null')),  -- optional presentation
    description TEXT CHECK (typeof(description) IN ('text', 'null')),
    sort_order  INTEGER CHECK (typeof(sort_order) IN ('integer', 'null')),
    conflict    TEXT NOT NULL DEFAULT 'manual' CHECK (typeof(conflict) = 'text')
                CHECK (conflict IN ('manual', 'prefer-incoming', 'prefer-existing')),
    -- What the collection is for (§14), as its source says, NULL when it says
    -- nothing, or as its owner made it for `attachments`: a mail role is the
    -- JMAP Mailbox/role vocabulary (the IANA IMAP mailbox name attributes
    -- lowercased, plus inbox), and `default` marks the calendar or address
    -- book a source writes to when none is named, and `attachments` the file
    -- collection holding an account's stand-ins (§14.3). An open vocabulary,
    -- checked by no constraint: a reader reads a role it does not know as none.
    role        TEXT CHECK (typeof(role) IN ('text', 'null')),
    -- Handle-space epoch, bumped by the owner on a backend identity reset, so a
    -- reader derives an IMAP UIDVALIDITY from the store alone (§12).
    generation  INTEGER NOT NULL DEFAULT 1 CHECK (typeof(generation) = 'integer'),
    -- The change stamp (§4.5), maintained by the triggers below.
    changed     INTEGER NOT NULL DEFAULT 0 CHECK (typeof(changed) = 'integer')
);

-- The merged view's filter axis. Partial: a single-account store writes no
-- account and pays for no index.
CREATE INDEX collections_by_account ON collections(account) WHERE account IS NOT NULL;
-- The change feed's collection half (§4.5).
CREATE INDEX collections_by_changed ON collections(changed);
-- One holder per role within an account and a kind (§14).
CREATE UNIQUE INDEX collections_by_role ON collections(ifnull(account, ''), kind, role)
WHERE role IS NOT NULL;

-- A role set on one collection leaves the one that held it, so moving a role is
-- one statement and the index above never sees two holders.
CREATE TRIGGER collections_role_moves BEFORE UPDATE OF role ON collections
WHEN NEW.role IS NOT NULL AND OLD.role IS NOT NEW.role
BEGIN
    UPDATE collections SET role = NULL
    WHERE id IS NOT NEW.id AND account IS NEW.account AND kind = NEW.kind AND role = NEW.role;
END;

-- A renamed collection restamps its items under the new id (§4.5), else a
-- consumer keyed on the old id drops them and never learns the new one, and
-- counts in purges, since the keys under the old id are gone like a purged
-- row's and a consumer reconciles its keys when that count moves.
CREATE TRIGGER collections_restamp_items AFTER UPDATE OF id ON collections
WHEN OLD.id IS NOT NEW.id
BEGIN
    UPDATE items SET changed = -1 WHERE collection IN (OLD.id, NEW.id);
    UPDATE store_meta SET purges = purges + 1 WHERE id = 1;
END;

-- A deleted collection leaves no stamp, like a purged row (§4.5), and an
-- empty one takes no item whose purge would count: it counts here, so a
-- consumer of the feed learns that a collection went and reconciles its keys.
CREATE TRIGGER collections_count_delete AFTER DELETE ON collections
BEGIN
    UPDATE store_meta SET purges = purges + 1 WHERE id = 1;
END;

-- One row per source syncing a collection (a server, a phone): its sync
-- cursor, the coverage that cursor serves, and the round under way (SYNC.md
-- §5). A scope is `[since, until)` on the mail summary's `date`, NULL bounds
-- open; the coverage is the scope of the last round that closed, and the
-- store is complete over it.
CREATE TABLE sources (
    collection       TEXT NOT NULL CHECK (typeof(collection) = 'text') REFERENCES collections(id) ON UPDATE CASCADE ON DELETE CASCADE,
    source           TEXT NOT NULL CHECK (typeof(source) = 'text') CHECK (source != ''),  -- source id ('left', 'right', 'phone'), never empty
    checkpoint       BLOB CHECK (typeof(checkpoint) IN ('blob', 'null')),  -- opaque remote cursor (QRESYNC/JMAP state, DAV sync-token)
    -- The coverage's floor and its exclusive ceiling, NULL unbounded: an
    -- instant at seconds precision, as summary.date (§13).
    covered_since    TEXT CHECK (typeof(covered_since) IN ('text', 'null'))
                     CHECK (covered_since GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z'),
    covered_until    TEXT CHECK (typeof(covered_until) IN ('text', 'null'))
                     CHECK (covered_until GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z'),
    -- When the last round closed, stamped by SQLite; NULL is never complete,
    -- and then the coverage carries no bound.
    covered_at       TEXT CHECK (typeof(covered_at) IN ('text', 'null')) CHECK (covered_at IS NOT NULL OR (covered_since IS NULL AND covered_until IS NULL))
                     CHECK (covered_at GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9].[0-9][0-9][0-9]Z'),
    -- The last round id drawn (open_round), so a restarted round stamps
    -- afresh and a binding's stamp names one listing.
    round            INTEGER NOT NULL DEFAULT 0 CHECK (typeof(round) = 'integer'),
    -- The open round's scope, shaped as the coverage's, NULL bounds open.
    round_since      TEXT CHECK (typeof(round_since) IN ('text', 'null'))
                     CHECK (round_since GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z'),
    round_until      TEXT CHECK (typeof(round_until) IN ('text', 'null'))
                     CHECK (round_until GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z'),
    round_cursor     BLOB CHECK (typeof(round_cursor) IN ('blob', 'null')),  -- the connector's resume cursor, opaque
    round_checkpoint BLOB CHECK (typeof(round_checkpoint) IN ('blob', 'null')),  -- the checkpoint the round lands when it closes
    -- When the open round began, stamped by SQLite; NULL is no round open,
    -- and then it carries nothing.
    round_started_at TEXT CHECK (typeof(round_started_at) IN ('text', 'null')) CHECK (round_started_at IS NOT NULL OR (round_since IS NULL AND
                     round_until IS NULL AND round_cursor IS NULL AND round_checkpoint IS NULL))
                     CHECK (round_started_at GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9].[0-9][0-9][0-9]Z'),
    -- Whether the open round lists only the band its coverage lacks, whose
    -- absence infers no delete of an undated member; 0 with no round open.
    round_band       INTEGER NOT NULL DEFAULT 0 CHECK (typeof(round_band) = 'integer') CHECK (round_band = 0 OR (round_band = 1 AND round_started_at IS NOT NULL)),
    PRIMARY KEY (collection, source)
);

-- The temporal coverage over every collection (SEARCH.md §8.2, covered_all):
-- the latest floor and the earliest ceiling among the sources that closed a
-- round, each the end of its index, and the sources that never closed one,
-- an index empty at rest, so the roll seeks three entries rather than
-- reading every source. Partial, so a source with no bound adds nothing.
CREATE INDEX sources_by_since ON sources(covered_since) WHERE covered_at IS NOT NULL AND covered_since IS NOT NULL;
CREATE INDEX sources_by_until ON sources(covered_until) WHERE covered_at IS NOT NULL AND covered_until IS NOT NULL;
CREATE INDEX sources_filling ON sources(collection) WHERE covered_at IS NULL;

-- A coverage a reader lists with the collection (list_collections) moves
-- the collection's stamp (§4.5), so a window saying "mail since" follows the
-- feed rather than polling the sync state.
CREATE TRIGGER sources_stamp_coverage AFTER UPDATE OF covered_since, covered_until, covered_at
ON sources
WHEN OLD.covered_since IS NOT NEW.covered_since
  OR OLD.covered_until IS NOT NEW.covered_until
  OR OLD.covered_at IS NOT NEW.covered_at
BEGIN
    UPDATE collections SET changed = (SELECT next_change FROM store_meta WHERE id = 1)
    WHERE id = NEW.collection;
    UPDATE store_meta SET next_change = next_change + 1 WHERE id = 1;
END;

-- What each source can do (§15.6), declared by the owner, read by producers
-- before they enqueue. A declaration writes every capability of the kinds the
-- source syncs, `none` included, so a source with no row is undeclared and
-- gated by nothing. A row naming a collection overrides the source's row there
-- (a read-only calendar in a writable account); NULL is the source-wide row,
-- so the key is an expression index. A source id names one remote store-wide;
-- `account` is the one it syncs for, NULL in a single-account store, so a
-- source is a candidate for its account's intents before it has synced a
-- collection.
CREATE TABLE capabilities (
    account    TEXT CHECK (typeof(account) IN ('text', 'null')) CHECK (account != ''),
    source     TEXT NOT NULL CHECK (typeof(source) = 'text') CHECK (source != ''),
    collection TEXT CHECK (typeof(collection) IN ('text', 'null')) REFERENCES collections(id) ON UPDATE CASCADE ON DELETE CASCADE,
    capability TEXT NOT NULL CHECK (typeof(capability) = 'text'),  -- Annex B name, or an `x-` one
    support    TEXT NOT NULL CHECK (typeof(support) = 'text') CHECK (support IN ('full', 'partial', 'none')),
    detail     TEXT CHECK (typeof(detail) IN ('text', 'null'))  -- what is missing or why, for a human
);

CREATE UNIQUE INDEX capabilities_key ON capabilities(source, ifnull(collection, ''), capability);

-- The source the user chose to perform an intent capability when several of
-- an account's sources declare it (§15.6), written by the owner applying a
-- `set-performer` action. `account` is NULL in a single-account store, so the
-- key is an expression index rather than a primary key.
CREATE TABLE performers (
    account    TEXT CHECK (typeof(account) IN ('text', 'null')) CHECK (account != ''),
    capability TEXT NOT NULL CHECK (typeof(capability) = 'text'),
    source     TEXT NOT NULL CHECK (typeof(source) = 'text') CHECK (source != '')
);

CREATE UNIQUE INDEX performers_key ON performers(ifnull(account, ''), capability);

-- Content-addressed body index; the bytes live in blob files (§5).
--
-- `id` is the object's key, the one every pointer at it carries (§4.3): drawn
-- at insert above every id drawn before (AUTOINCREMENT), so a new body's
-- entries land at the end of every index on a pointer, and never reused, so
-- no pointer comes to name another body. Never shown: a statement takes and
-- answers a body by its hash (§4.4), which only this row holds.
--
-- A hash is a name, never a path: the BLAKE3 digest as 52 characters of
-- lowercase base32 (§5), so no row names `..`, a separator or anything else a
-- path could be built from.
--
-- The refcount floor is load-bearing rather than tidy: a double release either
-- fails every later write on a foreign key that names neither the object nor
-- the miscount, or goes unnoticed entirely. The CHECK moves the failure to the
-- statement that caused it (§7).
CREATE TABLE objects (
    id       INTEGER PRIMARY KEY AUTOINCREMENT,
    hash     TEXT NOT NULL CHECK (typeof(hash) = 'text')
             CHECK (length(hash) = 52 AND hash NOT GLOB '*[^a-z2-7]*'),
    size     INTEGER NOT NULL CHECK (typeof(size) = 'integer') CHECK (size >= 0),  -- body length in bytes
    refcount INTEGER NOT NULL DEFAULT 0 CHECK (typeof(refcount) = 'integer') CHECK (refcount >= 0)
);

-- A body's name, one row each: what a statement naming a body by its hash
-- seeks (§4.4), and the one key of the object rows an insert does not append
-- to.
CREATE UNIQUE INDEX objects_by_hash ON objects(hash);

-- A collected object leaves no stamp either (§4.5): the index holds its text
-- until it learns the row is gone.
CREATE TRIGGER objects_count_collect AFTER DELETE ON objects
BEGIN
    UPDATE store_meta SET purges = purges + 1 WHERE id = 1;
END;

-- The shared truth of one logical item, keyed by its cross-source link id.
-- `deleted` lingers while a removal propagates to the other sources; once the
-- last one has dropped it the row is retained rather than deleted (non-NULL
-- `retained_at`), keeping its body pinned until an explicit purge (§11).
--
-- What the item says about itself is its summary row (§4.4).
--
-- `id` is the placement's own key, which every child of it carries: never
-- reused (AUTOINCREMENT) and never shown, a consumer keeping (collection,
-- seq) and a writer (collection, link_id), the key the store files it under.
CREATE TABLE items (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    collection      TEXT NOT NULL CHECK (typeof(collection) = 'text') REFERENCES collections(id) ON UPDATE CASCADE ON DELETE CASCADE,
    link_id         TEXT NOT NULL CHECK (typeof(link_id) = 'text') CHECK (link_id != ''),  -- never empty; the key the item is filed under: the identity hint, escaped as esc:<hint> when it begins like a derived key, a kind fallback, or a minted dup:<hint>#<handle> (§9)
    seq             INTEGER NOT NULL CHECK (typeof(seq) = 'integer') CHECK (seq >= 1),  -- public id, shared by every placement of the link id (§9.1)
    -- Whether the flag set is known: 1 marks and keywords are the set, both
    -- empty being known-empty; 0 unknown, and then both are empty.
    flags_known     INTEGER NOT NULL DEFAULT 0 CHECK (typeof(flags_known) = 'integer') CHECK (flags_known IN (0, 1)),
    -- The system flags of the set (§13), by their exact bytes: \Seen 1,
    -- \Answered 2, \Flagged 4, \Draft 8, \Deleted 16; every other flag is in
    -- keywords. 0 while the set is unknown.
    marks           INTEGER NOT NULL DEFAULT 0 CHECK (typeof(marks) = 'integer') CHECK (marks BETWEEN 0 AND 31),
    -- Every other flag of the set (§13), each printable and holding no space,
    -- sorted bytewise and joined by one space, '' for none: a reader appends
    -- it to the system flags and splits the set back (§14.1). The sort, the
    -- single spelling of each flag and the exclusion of the five system
    -- flags are the writer's duty; the schema holds the shape alone.
    keywords        TEXT NOT NULL DEFAULT '' CHECK (typeof(keywords) = 'text')
                    CHECK (keywords NOT GLOB '*[^ -~]*' AND keywords NOT GLOB ' *'
                           AND keywords NOT GLOB '* ' AND keywords NOT GLOB '*  *'),
    object          INTEGER CHECK (typeof(object) IN ('integer', 'null')) REFERENCES objects(id),  -- current body, NULL until hydrated
    sort_key        TEXT NOT NULL DEFAULT '' CHECK (typeof(sort_key) = 'text'),  -- the kind's ordering key, '' when unknown (§9.3)
    -- The detail ladder: 1 meta, 2 full (§13).
    level           INTEGER NOT NULL CHECK (typeof(level) = 'integer') CHECK (level IN (1, 2)),
    deleted         INTEGER NOT NULL DEFAULT 0 CHECK (typeof(deleted) = 'integer') CHECK (deleted IN (0, 1)),  -- 1 while a delete propagates across sources
    retained_at     TEXT CHECK (typeof(retained_at) IN ('text', 'null'))  -- the instant the last binding vanished (§11), the shape of §13
                    CHECK (retained_at GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9].[0-9][0-9][0-9]Z'),
    retained_by     TEXT CHECK (typeof(retained_by) IN ('text', 'null')),  -- the source whose removal retired it, diagnostic
    conflicted      INTEGER NOT NULL DEFAULT 0 CHECK (typeof(conflicted) = 'integer') CHECK (conflicted IN (0, 1)),  -- 1 while a cross-source content conflict is unresolved
    conflict_object INTEGER CHECK (typeof(conflict_object) IN ('integer', 'null')) REFERENCES objects(id),  -- the diverging body a manual conflict recorded
    changed         INTEGER NOT NULL DEFAULT 0 CHECK (typeof(changed) = 'integer'),  -- the change stamp (§4.5), trigger-maintained
    -- 1 while the row is live, holds a body and a source of its collection
    -- binds it not (§4.6): the lacking mark, trigger-maintained.
    lacks           INTEGER NOT NULL DEFAULT 0 CHECK (typeof(lacks) = 'integer') CHECK (lacks IN (0, 1)),
    UNIQUE (collection, link_id),
    -- What a binding's foreign key names, so its collection is its item's.
    UNIQUE (id, collection),
    -- The terminal states §11 and §10 describe, held by the schema.
    CHECK (retained_at IS NULL OR deleted = 1),
    CHECK (retained_by IS NULL OR retained_at IS NOT NULL),
    CHECK (conflicted = 1 OR conflict_object IS NULL),
    CHECK (flags_known = 1 OR (marks = 0 AND keywords = ''))
);

-- Resolves a public id back to the internal link id.
CREATE UNIQUE INDEX items_by_seq ON items(collection, seq);
-- "Does this link id already have a seq?", which is what makes every placement
-- share one, and list_link_placements (§9.2).
CREATE INDEX items_by_link ON items(link_id);
-- The trash view (§11, §14.1): every deleted row, retained or still
-- propagating. It leads with `seq` because the listing pages on the public
-- id: ordering by anything else sorts every such row to return one page.
CREATE INDEX items_deleted ON items(collection, seq) WHERE deleted = 1;
-- Orders a collection by the kind's own key, `seq` breaking the tie so a keyset
-- page over a non-unique key is total. Partial on the live rows, which every
-- listing filters on, so a mailbox whose server expunged most of it does not
-- page past its own trash (§14.1). A page over a set of collections seeks it
-- once per collection and merges what each answers (§9.3).
CREATE INDEX items_by_sort ON items(collection, sort_key, seq, marks) WHERE deleted = 0;
-- The unread mail of a collection in its order (count_unread, a page under
-- the read filter): partial on the bit, so a mailbox mostly read holds few.
CREATE INDEX items_unread ON items(collection, sort_key, seq) WHERE deleted = 0 AND marks & 1 = 0;
-- The retained rows by the instant they were retired (§11.2), so a purge below
-- a cutoff seeks it and retained_bytes reads it alone. Partial: a live row, or
-- a tombstone a source still binds, is not in it.
CREATE INDEX items_by_retained ON items(retained_at, object) WHERE retained_at IS NOT NULL;
-- The items waiting for a cross-source decision (list_conflicted_items).
-- Partial, empty at rest.
CREATE INDEX items_conflicted ON items(collection, seq) WHERE conflicted = 1;
-- The store-global lookup of a public id (§9.1), which items_by_seq cannot
-- serve without scanning: it leads with the collection.
CREATE INDEX items_by_seq_global ON items(seq);
-- The change feed (§4.5): what moved since a stamp is a range seek.
CREATE INDEX items_by_changed ON items(changed);

-- The change stamps (§4.5), drawn here so no writer plumbs them. An update
-- stamps only when an observable column moved, so a restated row stamps
-- nothing; a delete cannot stamp the row it removes and counts a purge. A
-- writer asks for a stamp by setting `changed` to -1 (stamp_item), and the
-- request trigger draws it, so every stamp is drawn here and no two rows
-- share one.
CREATE TRIGGER items_stamp_insert AFTER INSERT ON items
BEGIN
    UPDATE items SET changed = (SELECT next_change FROM store_meta WHERE id = 1)
    WHERE id = NEW.id;
    UPDATE store_meta SET next_change = next_change + 1 WHERE id = 1;
END;

CREATE TRIGGER items_stamp_update AFTER UPDATE OF
    flags_known, marks, keywords, object, sort_key, level, deleted, retained_at, conflicted, conflict_object
ON items
WHEN OLD.flags_known IS NOT NEW.flags_known
  OR OLD.marks IS NOT NEW.marks
  OR OLD.keywords IS NOT NEW.keywords
  OR OLD.object IS NOT NEW.object
  OR OLD.sort_key IS NOT NEW.sort_key
  OR OLD.level IS NOT NEW.level
  OR OLD.deleted IS NOT NEW.deleted
  OR OLD.retained_at IS NOT NEW.retained_at
  OR OLD.conflicted IS NOT NEW.conflicted
  OR OLD.conflict_object IS NOT NEW.conflict_object
BEGIN
    UPDATE items SET changed = (SELECT next_change FROM store_meta WHERE id = 1)
    WHERE id = NEW.id;
    UPDATE store_meta SET next_change = next_change + 1 WHERE id = 1;
END;

CREATE TRIGGER items_stamp_request AFTER UPDATE OF changed ON items
WHEN NEW.changed = -1
BEGIN
    UPDATE items SET changed = (SELECT next_change FROM store_meta WHERE id = 1)
    WHERE id = NEW.id;
    UPDATE store_meta SET next_change = next_change + 1 WHERE id = 1;
END;

CREATE TRIGGER items_count_purge AFTER DELETE ON items
BEGIN
    UPDATE store_meta SET purges = purges + 1 WHERE id = 1;
END;

CREATE TRIGGER collections_stamp_insert AFTER INSERT ON collections
BEGIN
    UPDATE collections SET changed = (SELECT next_change FROM store_meta WHERE id = 1)
    WHERE id = NEW.id;
    UPDATE store_meta SET next_change = next_change + 1 WHERE id = 1;
END;

CREATE TRIGGER collections_stamp_update AFTER UPDATE OF
    id, account, kind, name, parent, color, description, sort_order, role, generation
ON collections
WHEN OLD.id IS NOT NEW.id
  OR OLD.account IS NOT NEW.account
  OR OLD.kind IS NOT NEW.kind
  OR OLD.name IS NOT NEW.name
  OR OLD.parent IS NOT NEW.parent
  OR OLD.color IS NOT NEW.color
  OR OLD.description IS NOT NEW.description
  OR OLD.sort_order IS NOT NEW.sort_order
  OR OLD.role IS NOT NEW.role
  OR OLD.generation IS NOT NEW.generation
BEGIN
    UPDATE collections SET changed = (SELECT next_change FROM store_meta WHERE id = 1)
    WHERE id = NEW.id;
    UPDATE store_meta SET next_change = next_change + 1 WHERE id = 1;
END;

-- One source's binding of an item: its handle there, the three-way-merge base
-- last agreed with it, and whether its own sync is stuck on a conflict.
CREATE TABLE bindings (
    item              INTEGER NOT NULL CHECK (typeof(item) = 'integer'),
    -- The item's collection, kept for the handle index and held equal to it by
    -- the foreign key below, which a rename cascades through.
    collection        TEXT NOT NULL CHECK (typeof(collection) = 'text'),
    source            TEXT NOT NULL CHECK (typeof(source) = 'text') CHECK (source != ''),
    -- The item's backend id on this source (IMAP UID, DAV href). Bound once:
    -- a write resolving this binding to another handle is refused, and the one
    -- licensed rebind is the handle-space rebuild (§10, §12).
    handle            TEXT NOT NULL CHECK (typeof(handle) = 'text') CHECK (handle != ''),
    -- Whether the base flag set is known, as items.flags_known says of the
    -- item's: 1 base_marks and base_keywords are the set, 0 unknown.
    base_flags_known  INTEGER NOT NULL DEFAULT 0 CHECK (typeof(base_flags_known) = 'integer') CHECK (base_flags_known IN (0, 1)),
    -- The base's system flags, as items.marks holds the item's (§13).
    base_marks        INTEGER NOT NULL DEFAULT 0 CHECK (typeof(base_marks) = 'integer') CHECK (base_marks BETWEEN 0 AND 31),
    -- The base's other flags, spelled as items.keywords and written on the
    -- same duty: sorted bytewise, no system flag. A base carries no stamp.
    base_keywords     TEXT NOT NULL DEFAULT '' CHECK (typeof(base_keywords) = 'text')
                      CHECK (base_keywords NOT GLOB '*[^ -~]*' AND base_keywords NOT GLOB ' *'
                             AND base_keywords NOT GLOB '* ' AND base_keywords NOT GLOB '*  *'),
    base_object       INTEGER CHECK (typeof(base_object) IN ('integer', 'null')) REFERENCES objects(id),
    base_revision     TEXT CHECK (typeof(base_revision) IN ('text', 'null')),  -- etag/modseq for mutable-content backends
    -- Whether a base exists at all, which its three value columns cannot say: a
    -- source reporting no revision, no body and no flags still agreed, and that
    -- agreement is what tells a pending push from a settled one (§13). The one
    -- witness: the CHECK below lets no value column state a base without it.
    base_present      INTEGER NOT NULL DEFAULT 0 CHECK (typeof(base_present) = 'integer') CHECK (base_present IN (0, 1)),
    -- This source diverged from its OWN remote (§10), unlike items.conflicted,
    -- which is the cross-source divergence.
    conflicted        INTEGER NOT NULL DEFAULT 0 CHECK (typeof(conflicted) = 'integer') CHECK (conflicted IN (0, 1)),
    conflict_revision TEXT CHECK (typeof(conflict_revision) IN ('text', 'null')),  -- the remote revision observed when it did, or NULL
    -- The diverging remote body at that revision, so a resolver reads base,
    -- local and remote from the store and needs no credentials (§13). Pinned
    -- like any other reference while the binding stays conflicted.
    conflict_object   INTEGER CHECK (typeof(conflict_object) IN ('integer', 'null')) REFERENCES objects(id),
    -- The shared body this source last reconciled against, the base of the
    -- cross-source merge (§10, §13). base_object answers to the source's own
    -- remote and only a sync moves it, so a body this source folded in and has
    -- not pushed yet leaves it behind; read as the shared base it would have
    -- the source disagree with itself. Meaningful whether or not the binding
    -- is conflicted. Pinned like the base (§5): it is the common ancestor a
    -- merge reads, one body per binding, released when the binding next agrees.
    shared_object     INTEGER CHECK (typeof(shared_object) IN ('integer', 'null')) REFERENCES objects(id),
    -- The id the source's server gives the member's content (RFC 8474
    -- EMAILID, Gmail's X-GM-MSGID, JMAP's Email/id), as the source last
    -- stated it with the member's meta (SYNC.md §4), NULL where it stated
    -- none. Opaque, comparable only with another binding of the same
    -- source: two stating different ones never share a body by link id
    -- (lookup_objects, SYNC.md §6).
    server_object_id  TEXT CHECK (typeof(server_object_id) IN ('text', 'null')) CHECK (server_object_id != ''),
    -- The id of the last round whose listing carried this handle (SYNC.md
    -- §5), NULL until one did: a round's last page drops the in-scope
    -- bindings it did not stamp.
    round             INTEGER CHECK (typeof(round) IN ('integer', 'null')),
    -- The refusal standing on this binding (SYNC.md §4, §5): the reason the
    -- remote refused a change for good, scrubbed (§18), the idempotency key of
    -- that change, which the engine holds while it derives the same one, and
    -- the instant SQLite stamped it (refuse_binding). Cleared by the next
    -- accepted push (clear_refusal), gone with the binding.
    refusal           TEXT CHECK (typeof(refusal) IN ('text', 'null')),
    refused_key       TEXT CHECK (typeof(refused_key) IN ('text', 'null'))
                      CHECK (refused_key GLOB '[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]'),
    refused_at        TEXT CHECK (typeof(refused_at) IN ('text', 'null'))  -- the shape of §13
                      CHECK (refused_at GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9].[0-9][0-9][0-9]Z'),
    -- 1 while the placement may owe a push or a decision (§4.6): the owing
    -- mark, trigger-maintained.
    owes              INTEGER NOT NULL DEFAULT 0 CHECK (typeof(owes) = 'integer') CHECK (owes IN (0, 1)),
    PRIMARY KEY (item, source),
    -- A refusal states its reason, its key and its instant, or none of them.
    CHECK ((refusal IS NULL) = (refused_key IS NULL) AND (refusal IS NULL) = (refused_at IS NULL)),
    -- A binding that is not conflicted carries neither (§13).
    CHECK (conflicted = 1 OR (conflict_revision IS NULL AND conflict_object IS NULL)),
    CHECK (base_flags_known = 1 OR (base_marks = 0 AND base_keywords = '')),
    CHECK (base_present = 1 OR (base_flags_known = 0 AND base_object IS NULL AND base_revision IS NULL)),
    -- ON UPDATE as well as ON DELETE: renaming a collection cascades into
    -- items.collection, so its bindings follow it (§14).
    FOREIGN KEY (item, collection) REFERENCES items(id, collection) ON UPDATE CASCADE ON DELETE CASCADE
);

-- What an `add` carrying `supersedes` replaced (§15.3): the item it tombstoned,
-- keyed as that item, and the item the add created. The tombstone's remove is
-- held while the superseding item is a pending create (list_superseded_pending,
-- SYNC.md §5). Each end cascades with its item: a superseded row purged takes
-- its pair, and so does a superseding row purged, which then holds nothing.
CREATE TABLE supersessions (
    item    INTEGER NOT NULL CHECK (typeof(item) = 'integer') REFERENCES items(id) ON DELETE CASCADE,  -- the superseded item
    by_item INTEGER NOT NULL CHECK (typeof(by_item) = 'integer') REFERENCES items(id) ON DELETE CASCADE,  -- the item the add created
    PRIMARY KEY (item)
) WITHOUT ROWID;
-- The superseding end, which a purge of that item cascades by.
CREATE INDEX supersessions_by ON supersessions(by_item);

-- The summary (§4.4, Annex A): what a reader lists an item from without its
-- body, one row per item whatever its kind, cascading with it. Written by the
-- item's writer under Annex A; it references no object. `component` names the
-- Annex A section the row follows, and a column another component owns stays
-- NULL. A calendar resource is one VEVENT, VTODO or VJOURNAL set (Annex A.3 to
-- A.5): a start is carried verbatim with its parameters, the one resolved
-- instant being items.sort_key. A file (Annex A.7) is what its source or its
-- writer states, the bytes saying nothing of it: one row per placement, so a
-- file in two folders may carry two names, and `part` stays with the file
-- wherever it is placed.
CREATE TABLE summary (
    item          INTEGER PRIMARY KEY REFERENCES items(id) ON DELETE CASCADE,
    component     TEXT NOT NULL CHECK (typeof(component) = 'text')
                  CHECK (component IN ('mail', 'contact', 'event', 'task', 'journal', 'file')),
    uid           TEXT CHECK (typeof(uid) IN ('text', 'null')),  -- mail: the bare Message-ID, angle brackets stripped; contact, event, task, journal: the UID verbatim; file: NULL
    title         TEXT NOT NULL CHECK (typeof(title) = 'text'),  -- mail: the subject decoded (RFC 2047); contact: FN decoded (Annex A.2); event, task, journal: SUMMARY unescaped; file: its name in this collection; each may be empty
    -- mail (Annex A.1); every address is also a summary_value row
    sender        TEXT CHECK (typeof(sender) IN ('text', 'null')),  -- first From address, canonical (Annex A.6)
    sender_name   TEXT CHECK (typeof(sender_name) IN ('text', 'null')),  -- its display name, decoded, or NULL
    date          TEXT CHECK (typeof(date) IN ('text', 'null'))  -- RFC 3339 UTC Z at seconds precision, or NULL
                  CHECK (date GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z'),
    size          INTEGER CHECK (typeof(size) IN ('integer', 'null')) CHECK (size >= 0),  -- mail: the body's octets, else the source's figure (Annex A.1); file: the body's when held, else as stated; or NULL
    attachment    INTEGER CHECK (typeof(attachment) IN ('integer', 'null')) CHECK (attachment IN (0, 1)),  -- 1 has one, 0 has none, NULL not examined
    invitation    TEXT CHECK (typeof(invitation) IN ('text', 'null')),  -- the UID its first text/calendar part carries, NULL none or not examined
    -- contact (Annex A.2); every EMAIL is a summary_value row
    card_kind     TEXT CHECK (typeof(card_kind) IN ('text', 'null')),  -- KIND lowercased: individual, group, org, location; NULL when absent
    org           TEXT CHECK (typeof(org) IN ('text', 'null')),  -- first ORG component, unescaped, or NULL
    -- event, task, journal (Annex A.3 to A.5)
    location      TEXT CHECK (typeof(location) IN ('text', 'null')),  -- LOCATION unescaped, or NULL
    dtstart       TEXT CHECK (typeof(dtstart) IN ('text', 'null')),  -- the value verbatim
    dtstart_tzid  TEXT CHECK (typeof(dtstart_tzid) IN ('text', 'null')),  -- the TZID parameter, or NULL
    dtstart_value TEXT CHECK (typeof(dtstart_value) IN ('text', 'null')),  -- 'date-time' or 'date'
    dtend         TEXT CHECK (typeof(dtend) IN ('text', 'null')),  -- the value verbatim, or NULL
    recurring     INTEGER CHECK (typeof(recurring) IN ('integer', 'null')) CHECK (recurring IN (0, 1)),  -- 1 carries an RRULE or RDATE, 0 none, NULL not examined
    until         TEXT CHECK (typeof(until) IN ('text', 'null')),  -- the RRULE's UNTIL verbatim, or NULL
    -- task (Annex A.4)
    due           TEXT CHECK (typeof(due) IN ('text', 'null')),  -- the DUE value verbatim, or NULL
    due_tzid      TEXT CHECK (typeof(due_tzid) IN ('text', 'null')),
    due_value     TEXT CHECK (typeof(due_value) IN ('text', 'null')),
    status        TEXT CHECK (typeof(status) IN ('text', 'null')),  -- STATUS uppercased verbatim, or NULL
    completed     TEXT CHECK (typeof(completed) IN ('text', 'null')),  -- COMPLETED verbatim (always UTC per RFC 5545), or NULL
    percent       INTEGER CHECK (typeof(percent) IN ('integer', 'null')),  -- PERCENT-COMPLETE, or NULL
    priority      INTEGER CHECK (typeof(priority) IN ('integer', 'null')) CHECK (priority BETWEEN 0 AND 9),  -- PRIORITY, or NULL
    parent        TEXT CHECK (typeof(parent) IN ('text', 'null')),  -- the UID the first parent RELATED-TO names, or NULL
    mid           TEXT CHECK (typeof(mid) IN ('text', 'null')),  -- the Message-ID the first mid: URI names, bare, or NULL
    created       TEXT CHECK (typeof(created) IN ('text', 'null')),  -- CREATED, else DTSTAMP, as an instant (Annex A.4), or NULL
    -- file (Annex A.7)
    media_type    TEXT CHECK (typeof(media_type) IN ('text', 'null')),  -- type/subtype lowercased, no parameter, or NULL
    part          TEXT CHECK (typeof(part) IN ('text', 'null')),  -- an attachment's IMAP section in its message, or NULL
    -- A column another component owns is NULL.
    CHECK (component = 'mail'
           OR (sender IS NULL AND sender_name IS NULL AND date IS NULL
               AND attachment IS NULL AND invitation IS NULL)),
    CHECK (component IN ('mail', 'file') OR size IS NULL),
    CHECK (component <> 'file' OR uid IS NULL),
    CHECK (component = 'contact' OR (card_kind IS NULL AND org IS NULL)),
    CHECK (component = 'event' OR (location IS NULL AND dtend IS NULL)),
    CHECK (component IN ('event', 'task', 'journal')
           OR (dtstart IS NULL AND dtstart_tzid IS NULL AND dtstart_value IS NULL)),
    CHECK (component IN ('event', 'task') OR (recurring IS NULL AND until IS NULL)),
    CHECK (component = 'task'
           OR (due IS NULL AND due_tzid IS NULL AND due_value IS NULL AND status IS NULL
               AND completed IS NULL AND percent IS NULL AND priority IS NULL
               AND parent IS NULL AND mid IS NULL AND created IS NULL)),
    CHECK (component = 'file' OR (media_type IS NULL AND part IS NULL))
);

-- The mail inviting to a calendar item, for link_invitations_to (§14.2), the
-- tasks naming a calendar item their parent, and those naming a mail, for
-- link_parents_to and link_sources_to. Partial: most items name none.
CREATE INDEX summary_by_invitation ON summary(invitation) WHERE invitation IS NOT NULL;
CREATE INDEX summary_by_parent ON summary(parent) WHERE parent IS NOT NULL;
CREATE INDEX summary_by_mid ON summary(mid) WHERE mid IS NOT NULL;

-- The lists a summary carries (§4.4, Annex A), whatever the item's kind,
-- `position` their 0-based document order within the role. The people an item
-- names (Annex A.6) under the roles from, to, cc, bcc, email, organizer,
-- attendee and contact (§13), `value` the canonical addr-spec and `name` its
-- display name; a message's In-Reply-To ids (Annex A.1) under `in-reply-to`,
-- bare; a task's CATEGORIES values (Annex A.4) under `category`, decoded.
CREATE TABLE summary_value (
    item       INTEGER NOT NULL CHECK (typeof(item) = 'integer') REFERENCES items(id) ON DELETE CASCADE,
    role       TEXT NOT NULL CHECK (typeof(role) = 'text'),
    position   INTEGER NOT NULL CHECK (typeof(position) = 'integer'),
    value      TEXT NOT NULL CHECK (typeof(value) = 'text'),
    name       TEXT CHECK (typeof(name) IN ('text', 'null')),  -- an address's display name, decoded, or NULL
    CHECK (role NOT IN ('in-reply-to', 'category') OR name IS NULL),
    PRIMARY KEY (item, role, position)
) WITHOUT ROWID;

-- The person axis and the reply axis: every placement naming one address, by
-- role, and every message replying to one id. The table has no rowid, so the
-- index carries the rest of its key and names each placement without reading
-- the row.
CREATE INDEX summary_value_by_value ON summary_value(value, role);

-- A reference from one item to another, whatever their kinds and wherever they
-- are filed (§4.3, §14.2): an endpoint is a kind and a link id, so one held in
-- three collections is one endpoint, and a move keeps it. No foreign key, for
-- the same reason: the endpoint outlives any one row. A fact recorded once and
-- never recomputed, which no store requires.
CREATE TABLE item_reference (
    from_kind    TEXT NOT NULL CHECK (typeof(from_kind) = 'text'),  -- the referring item's collection kind
    from_link_id TEXT NOT NULL CHECK (typeof(from_link_id) = 'text'),
    to_kind      TEXT NOT NULL CHECK (typeof(to_kind) = 'text'),  -- the referred item's collection kind
    to_link_id   TEXT NOT NULL CHECK (typeof(to_link_id) = 'text'),
    -- What the reference says: a name pimdir gives, or an application's own
    -- starting with x-, as for capabilities.
    role         TEXT NOT NULL CHECK (typeof(role) = 'text') CHECK (role IN ('attachment', 'invitation', 'sender', 'parent', 'source', 'related')
                                      OR (substr(role, 1, 2) = 'x-' AND length(role) > 2)),
    origin       TEXT NOT NULL CHECK (typeof(origin) = 'text') CHECK (origin IN ('auto', 'user')),  -- a writer's rule, or a person
    created_at   TEXT NOT NULL CHECK (typeof(created_at) = 'text')  -- stamped by add_reference (§13)
                 CHECK (created_at GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9].[0-9][0-9][0-9]Z'),
    -- The key leads with the link id, which items_drop_references seeks by.
    PRIMARY KEY (from_link_id, from_kind, to_link_id, to_kind, role),
    CHECK (from_kind != to_kind OR from_link_id != to_link_id),
    -- A writer-derived key names no identity (§9), so no endpoint is one: a
    -- message under it, and a part of such a message, take no reference. A
    -- stated identity beginning like one is keyed esc:<hint> and passes.
    CHECK (NOT (from_link_id GLOB 'alt:*' OR from_link_id GLOB 'dup:*' OR from_link_id GLOB 'hash:*'
                OR from_link_id GLOB 'part:alt:*' OR from_link_id GLOB 'part:dup:*')),
    CHECK (NOT (to_link_id GLOB 'alt:*' OR to_link_id GLOB 'dup:*' OR to_link_id GLOB 'hash:*'
                OR to_link_id GLOB 'part:alt:*' OR to_link_id GLOB 'part:dup:*'))
) WITHOUT ROWID;

-- references_to, and the trigger's seek on the other end.
CREATE INDEX item_reference_to ON item_reference(to_link_id, to_kind, from_link_id, from_kind, role);

-- A reference goes with the last row of either endpoint, live, tombstoned or
-- retained (§14.2): when a delete leaves no row of that link id in a collection
-- of that kind. A move, a retention and a purge of one copy among several keep
-- it; the purge or collection of the last copy, or its collection's delete,
-- takes it. Read from the reference's own kinds, since a collection deleted by
-- cascade is gone before its items are.
CREATE TRIGGER items_drop_references AFTER DELETE ON items
BEGIN
    DELETE FROM item_reference
    WHERE (from_link_id = OLD.link_id
           AND NOT EXISTS (SELECT 1 FROM items i JOIN collections c ON c.id = i.collection
                           WHERE i.link_id = OLD.link_id AND c.kind = item_reference.from_kind))
       OR (to_link_id = OLD.link_id
           AND NOT EXISTS (SELECT 1 FROM items i JOIN collections c ON c.id = i.collection
                           WHERE i.link_id = OLD.link_id AND c.kind = item_reference.to_kind));
END;

-- A file holding no body and bound by no source stands for an attachment
-- inside a message (§14.3), and goes once no reference names it: a message
-- gone with its last row takes it, through items_drop_references. A file with
-- a body, or one a source syncs, is never collected here. Only a reference
-- with a file end fires it, and it seeks the ends' link ids on items_by_link
-- (`+` keeping the body test off any other index).
CREATE TRIGGER item_reference_collects_files AFTER DELETE ON item_reference
WHEN OLD.from_kind = 'application/octet-stream' OR OLD.to_kind = 'application/octet-stream'
BEGIN
    DELETE FROM items
    WHERE link_id IN (CASE WHEN OLD.from_kind = 'application/octet-stream' THEN OLD.from_link_id END,
                      CASE WHEN OLD.to_kind = 'application/octet-stream' THEN OLD.to_link_id END)
      AND +object IS NULL
      AND (SELECT kind FROM collections c WHERE c.id = items.collection) = 'application/octet-stream'
      AND NOT EXISTS (SELECT 1 FROM bindings b WHERE b.item = items.id)
      AND NOT EXISTS (SELECT 1 FROM item_reference r
                      WHERE (r.from_link_id = items.link_id AND r.from_kind = 'application/octet-stream')
                         OR (r.to_link_id = items.link_id AND r.to_kind = 'application/octet-stream'));
END;

-- An item's properties (§4.3): local state a person or an application keeps
-- on an item and no source carries, a local label among them. Keyed by the
-- public id (§9.1), so a property follows the item into every collection and
-- account filing it, through its retention, its restore and a rekey, and goes
-- with the last row holding the seq. Multi-valued, each value held once per
-- key. No foreign key, since a seq is no row's key: the triggers below hold
-- it. Never read by sync, never in a binding, never pushed (SYNC.md §3). A
-- key is `<namespace>/<name>`, each part of [a-z0-9._-], at most 64 bytes; a
-- value is 1 to 1,024 bytes of UTF-8 holding no NUL (§13).
CREATE TABLE item_property (
    seq   INTEGER NOT NULL CHECK (typeof(seq) = 'integer') CHECK (seq >= 1),
    key   TEXT    NOT NULL CHECK (typeof(key) = 'text')
          CHECK (length(key) <= 64 AND key NOT GLOB '*[^a-z0-9._/-]*'
                 AND instr(key, '/') > 1 AND instr(key, '/') < length(key)
                 AND instr(substr(key, instr(key, '/') + 1), '/') = 0),
    value TEXT    NOT NULL CHECK (typeof(value) = 'text')
          CHECK (length(CAST(value AS BLOB)) BETWEEN 1 AND 1024
                 AND instr(CAST(value AS BLOB), x'00') = 0),
    PRIMARY KEY (seq, key, value)
) WITHOUT ROWID;

-- The holders of a key and a value (list_value_holders), and the values a key
-- holds (list_property_values), which label: and property: read (SEARCH.md
-- §8). The table has no rowid, so the index carries the seq and names each
-- holder without reading the row.
CREATE INDEX item_property_by_value ON item_property(key, value);

-- A property names an item the store holds, live, tombstoned or retained: a
-- seq no row of items holds takes none.
CREATE TRIGGER item_property_needs_item BEFORE INSERT ON item_property
WHEN NOT EXISTS (SELECT 1 FROM items WHERE seq = NEW.seq)
BEGIN
    SELECT RAISE(ABORT, 'no item holds the seq');
END;

-- At most 64 values per key and item (§13): the 65th is refused, a value the
-- key holds already being no new one.
CREATE TRIGGER item_property_bounded BEFORE INSERT ON item_property
WHEN (SELECT count(*) FROM item_property WHERE seq = NEW.seq AND key = NEW.key) >= 64
 AND NOT EXISTS (SELECT 1 FROM item_property
                 WHERE seq = NEW.seq AND key = NEW.key AND value = NEW.value)
BEGIN
    SELECT RAISE(ABORT, 'a key holds 64 values');
END;

-- A value added or removed requests the stamp of every row holding the seq
-- (§4.5), live or not, so the change feed carries it; a value added again,
-- which moves no row, stamps nothing.
CREATE TRIGGER item_property_stamp_insert AFTER INSERT ON item_property
BEGIN
    UPDATE items SET changed = -1 WHERE seq = NEW.seq;
END;

CREATE TRIGGER item_property_stamp_delete AFTER DELETE ON item_property
BEGIN
    UPDATE items SET changed = -1 WHERE seq = OLD.seq;
END;

-- A property goes with the last row holding its seq (§11.2, §11.5): a purge,
-- an eviction, an unbound item's delete or its collection's. A retention, a
-- move and the loss of one row among several keep it.
CREATE TRIGGER items_drop_properties AFTER DELETE ON items
WHEN NOT EXISTS (SELECT 1 FROM items WHERE seq = OLD.seq)
BEGIN
    DELETE FROM item_property WHERE seq = OLD.seq;
END;

-- The action queue (§15): mutations requested by processes that do not own the
-- store, applied by the owner in append order.
CREATE TABLE queue (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,  -- global append order
    created_at  TEXT    NOT NULL CHECK (typeof(created_at) = 'text')  -- stamped by SQLite, the shape of §13
                CHECK (created_at GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9].[0-9][0-9][0-9]Z'),
    producer    TEXT    NOT NULL CHECK (typeof(producer) = 'text'),  -- enqueuing process, diagnostic
    -- A collection holding a pending or parked action is not deleted (§14): a
    -- cascade would drop the action, an intent included, with no receipt and
    -- no report. The operator cancels or lets the drain apply each row first.
    collection  TEXT    NOT NULL CHECK (typeof(collection) = 'text') REFERENCES collections(id) ON UPDATE CASCADE ON DELETE RESTRICT,
    action      TEXT    NOT NULL CHECK (typeof(action) = 'text'),  -- 'add' | 'set-flags' | 'remove' | 'move' | 'copy' | 'update' | 'set-performer' | an intent (§15.3, Annex B)
    payload     TEXT    NOT NULL CHECK (typeof(payload) = 'text'),  -- versioned JSON, shape per action (§15)
    -- The collection a `move` or a `copy` targets, or the one holding the item
    -- a superseding `add` replaces (§15.3): written beside the payload, so a
    -- rename follows it, and read in place of the payload's own.
    target_collection TEXT CHECK (typeof(target_collection) IN ('text', 'null')),
    object      INTEGER CHECK (typeof(object) IN ('integer', 'null')) REFERENCES objects(id),  -- pins the payload's body against the collector, or NULL
    attempts    INTEGER NOT NULL DEFAULT 0 CHECK (typeof(attempts) = 'integer') CHECK (attempts >= 0),
    error       TEXT CHECK (typeof(error) IN ('text', 'null'))  -- last failure; non-NULL means parked
);

-- What became of an applied action (§15.2, §15.4), keyed by the queue row's id:
-- application deletes the row, so a producer holding the id its enqueue
-- answered reads here that the row was applied and the seq of the item it
-- acted on, the one it created for an `add`, a `move` and a `copy`, and a
-- refusal standing there (load_receipt_refusals). Written by the owner in the
-- transaction applying the row, kept at least seven days and while a refusal
-- stands on its item, then pruned (prune_receipts). A cancelled row leaves
-- none. `seq` names no foreign key: a later move or purge retires the item,
-- and the receipt still says what the row acted on.
CREATE TABLE receipts (
    id         INTEGER PRIMARY KEY,        -- the applied queue row's id
    applied_at TEXT    NOT NULL CHECK (typeof(applied_at) = 'text')  -- stamped by SQLite, the shape of §13
               CHECK (applied_at GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9].[0-9][0-9][0-9]Z'),
    -- The collection the row was queued on, following its rename; NULL once
    -- that collection is gone, a `collection-delete` applied included, so the
    -- receipt outlives it and the intent never reads as withdrawn.
    collection TEXT    CHECK (typeof(collection) IN ('text', 'null')) REFERENCES collections(id) ON UPDATE CASCADE ON DELETE SET NULL,
    seq        INTEGER CHECK (typeof(seq) IN ('integer', 'null')) CHECK (seq >= 1)  -- the item the row acted on or created, else NULL
);

-- A reader overlays a collection's pending actions (§15.4).
CREATE INDEX queue_by_collection ON queue(collection, id);
-- The owner's drain, store-wide in append order, skipping the parked rows
-- (§15.2). Partial, so it holds only what is pending.
CREATE INDEX queue_pending ON queue(id) WHERE error IS NULL;

-- Cross-source identity lookup (dedup, thread stitching) and refcount
-- navigation. A pointer index is partial on the pointer being set: most rows
-- point at nothing, an equality implies the pointer is set, and so the foreign
-- key check of an object's delete seeks it as it would the whole index. A
-- pointer is the object's id, so a row naming a new body adds its entry at
-- the index's end.
CREATE INDEX items_by_object ON items(object) WHERE object IS NOT NULL;
-- The other side of items_by_object: each collection's live rows holding no
-- body, which the search part's coverage counts per collection (SEARCH.md
-- §8.2) by a seek. Partial, so a fully synced collection adds nothing, and
-- covering, the two columns it is partial on costing a byte each.
CREATE INDEX items_bodiless ON items(collection, deleted, object) WHERE object IS NULL AND deleted = 0;
CREATE INDEX bindings_by_object ON bindings(base_object) WHERE base_object IS NOT NULL;
-- The collector's scan (§5). Partial, so it holds only what is about to be
-- collected and is empty at rest.
CREATE INDEX objects_garbage ON objects(refcount) WHERE refcount <= 0;
-- The other four pointers at an object, so recompute_refcounts reaches every
-- reference by index rather than scanning items, bindings and queue once per
-- object.
CREATE INDEX items_by_conflict_object ON items(conflict_object) WHERE conflict_object IS NOT NULL;
CREATE INDEX bindings_by_conflict_object ON bindings(conflict_object) WHERE conflict_object IS NOT NULL;
CREATE INDEX bindings_by_shared_object ON bindings(shared_object) WHERE shared_object IS NOT NULL;
CREATE INDEX queue_by_object ON queue(object) WHERE object IS NOT NULL;
-- The bindings waiting for a decision (list_conflicted_bindings). Partial, so
-- it holds only what is outstanding and is empty at rest: a run reports that
-- count on every invocation, and without it the report scans every binding.
CREATE INDEX bindings_conflicted ON bindings(item, source) WHERE conflicted = 1;
-- Resolves a source handle back to its link id (link_for_handle), which is what
-- a batch dropping a placement needs: a drop names a handle, the shared item is
-- keyed by link id. UNIQUE, because a handle names one item per source (§10):
-- a write moving a handle onto another link id retires the old binding first,
-- and one that does not fails here rather than leaving two rows the lookup
-- answers from at random.
CREATE UNIQUE INDEX bindings_by_handle ON bindings(collection, source, handle);
-- The refusals standing in a collection (list_refusals), which a frontend's
-- queue view and an engine's load read. Partial, so it holds only what a
-- remote refused and is empty at rest.
CREATE INDEX bindings_refused ON bindings(collection, source) WHERE refusal IS NOT NULL;

-- The owing marks (§4.6): bindings.owes and items.lacks, which a delta's load
-- reads through a partial index each (list_owing_bindings,
-- list_lacking_items), so it costs what is owed rather than what the
-- collection holds. Each mark is a rule written once, as a view, and the
-- triggers below compute it again from the view after every write that can
-- move it, so a writer never writes one and the mark equals its rule at the
-- end of every statement. A recompute flips a mark only where it differs,
-- so a write restating a row moves no index entry.

-- A binding may owe a push or a decision: it or its item is conflicted, the
-- item is deleted, the binding has no base, a known flag set differs from a
-- known base (the system flags' bits, then the other flags' texts, which
-- their writers sort, so equal sets are equal texts), or the item holds a
-- body other than the base's (SYNC.md §3). A superset of the placements not
-- Clean.
CREATE VIEW binding_owes(item, source, owes) AS
SELECT b.item, b.source,
       b.conflicted = 1 OR i.conflicted = 1 OR i.deleted = 1
       OR b.base_present = 0
       OR (i.flags_known = 1 AND b.base_flags_known = 1
           AND (i.marks != b.base_marks OR i.keywords != b.base_keywords))
       OR (i.object IS NOT NULL AND i.object IS NOT b.base_object)
FROM bindings b JOIN items i ON i.id = b.item;

-- An item is lacking while it is live, holds a body and a source syncing its
-- collection (a row of sources) binds it not: a Created projection some
-- source is offered (SYNC.md §3).
CREATE VIEW item_lacks(item, lacks) AS
SELECT i.id,
       i.deleted = 0 AND i.object IS NOT NULL
       AND EXISTS (SELECT 1 FROM sources s
                   WHERE s.collection = i.collection
                     AND NOT EXISTS (SELECT 1 FROM bindings b
                                     WHERE b.item = i.id AND b.source = s.source))
FROM items i;

-- The owing mark follows the binding's own columns and its item's, the two
-- flag sets among them. A binding without its item is marked, a superset. A
-- flag of an item no source binds yet, as an import writes it, moves no mark.
CREATE TRIGGER bindings_owes_insert AFTER INSERT ON bindings
BEGIN
    UPDATE bindings SET owes = 1 - owes
    WHERE item = NEW.item AND source = NEW.source
      AND owes != coalesce((SELECT o.owes FROM binding_owes o
                            WHERE o.item = bindings.item AND o.source = bindings.source), 1);
END;

CREATE TRIGGER bindings_owes_update AFTER UPDATE OF
    item, source, conflicted, base_present, base_flags_known, base_marks, base_keywords, base_object
ON bindings
WHEN OLD.item IS NOT NEW.item
  OR OLD.source IS NOT NEW.source
  OR OLD.conflicted IS NOT NEW.conflicted
  OR OLD.base_present IS NOT NEW.base_present
  OR OLD.base_flags_known IS NOT NEW.base_flags_known
  OR OLD.base_marks IS NOT NEW.base_marks
  OR OLD.base_keywords IS NOT NEW.base_keywords
  OR OLD.base_object IS NOT NEW.base_object
BEGIN
    UPDATE bindings SET owes = 1 - owes
    WHERE item = NEW.item AND source = NEW.source
      AND owes != coalesce((SELECT o.owes FROM binding_owes o
                            WHERE o.item = bindings.item AND o.source = bindings.source), 1);
END;

CREATE TRIGGER items_owes_update AFTER UPDATE OF
    conflicted, deleted, flags_known, marks, keywords, object
ON items
WHEN OLD.conflicted IS NOT NEW.conflicted
  OR OLD.deleted IS NOT NEW.deleted
  OR OLD.flags_known IS NOT NEW.flags_known
  OR OLD.marks IS NOT NEW.marks
  OR OLD.keywords IS NOT NEW.keywords
  OR OLD.object IS NOT NEW.object
BEGIN
    UPDATE bindings SET owes = 1 - owes
    WHERE item = NEW.id
      AND owes != coalesce((SELECT o.owes FROM binding_owes o
                            WHERE o.item = bindings.item AND o.source = bindings.source), 1);
END;

-- The lacking mark follows the item's own columns, the bindings it gains and
-- loses, and the sources of its collection. A binding gained can only clear
-- it and one lost only set it, so each seeks the one item; a source added
-- marks what it binds not of its collection, which it is then owed.
CREATE TRIGGER items_lacks_insert AFTER INSERT ON items
WHEN NEW.deleted = 0 AND NEW.object IS NOT NULL
BEGIN
    UPDATE items SET lacks = 1 - lacks
    WHERE id = NEW.id
      AND lacks != (SELECT l.lacks FROM item_lacks l WHERE l.item = items.id);
END;

CREATE TRIGGER items_lacks_update AFTER UPDATE OF collection, deleted, object ON items
WHEN OLD.collection IS NOT NEW.collection
  OR OLD.deleted IS NOT NEW.deleted
  OR OLD.object IS NOT NEW.object
BEGIN
    UPDATE items SET lacks = 1 - lacks
    WHERE id = NEW.id
      AND lacks != (SELECT l.lacks FROM item_lacks l WHERE l.item = items.id);
END;

CREATE TRIGGER bindings_lacks_insert AFTER INSERT ON bindings
WHEN (SELECT lacks FROM items WHERE id = NEW.item) = 1
BEGIN
    UPDATE items SET lacks = 0
    WHERE id = NEW.item AND lacks = 1
      AND (SELECT l.lacks FROM item_lacks l WHERE l.item = items.id) = 0;
END;

CREATE TRIGGER bindings_lacks_delete AFTER DELETE ON bindings
BEGIN
    UPDATE items SET lacks = 1
    WHERE id = OLD.item AND lacks = 0
      AND (SELECT l.lacks FROM item_lacks l WHERE l.item = items.id) = 1;
END;

-- No statement rewrites a binding's item or source; a write that does is
-- one binding lost and another gained.
CREATE TRIGGER bindings_lacks_update AFTER UPDATE OF item, source ON bindings
WHEN OLD.item IS NOT NEW.item OR OLD.source IS NOT NEW.source
BEGIN
    UPDATE items SET lacks = 1 - lacks
    WHERE id IN (OLD.item, NEW.item)
      AND lacks != (SELECT l.lacks FROM item_lacks l WHERE l.item = items.id);
END;

CREATE TRIGGER sources_lacks_insert AFTER INSERT ON sources
BEGIN
    UPDATE items SET lacks = 1
    WHERE collection = NEW.collection AND deleted = 0 AND object IS NOT NULL AND lacks = 0
      AND NOT EXISTS (SELECT 1 FROM bindings b WHERE b.item = items.id AND b.source = NEW.source);
END;

CREATE TRIGGER sources_lacks_delete AFTER DELETE ON sources
BEGIN
    UPDATE items SET lacks = 0
    WHERE collection = OLD.collection AND lacks = 1
      AND (SELECT l.lacks FROM item_lacks l WHERE l.item = items.id) = 0;
END;

-- A rename's cascade moves a source and its items together, in either order,
-- and each side recomputes what the move can change.
CREATE TRIGGER sources_lacks_update AFTER UPDATE OF collection, source ON sources
WHEN OLD.collection IS NOT NEW.collection OR OLD.source IS NOT NEW.source
BEGIN
    UPDATE items SET lacks = 1 - lacks
    WHERE collection IN (OLD.collection, NEW.collection)
      AND lacks != (SELECT l.lacks FROM item_lacks l WHERE l.item = items.id);
END;

-- What a delta's load seeks (list_owing_bindings, list_lacking_items), each
-- holding what is owed alone and empty at rest.
CREATE INDEX bindings_owing ON bindings(collection, source, handle) WHERE owes = 1;
CREATE INDEX items_lacking ON items(collection, link_id) WHERE lacks = 1;
