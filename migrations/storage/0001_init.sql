-- pimdir store schema, version 1. Section references are to STORAGE.md.
--
-- Applied by a migration runner (§6) to a fresh database, inside a
-- transaction; the runner sets `PRAGMA user_version = 1` on success. Loads on
-- SQLite >= 3.18 (§4.1): a column's type is held by a CHECK on typeof() rather
-- than by STRICT, and nothing here calls a JSON function. While STORAGE.md is
-- a draft this file is edited in place, store_meta.format_version naming the
-- draft a store was written under (§4.2); once version 1 is released it never
-- changes, and a change to the schema is a migration to the next version (§6).

-- Pages freed by a delete go back to the filesystem when the owner asks
-- (§4.1). A database takes the mode only while it holds no table, so it is
-- set first.
PRAGMA auto_vacuum = INCREMENTAL;

-- Store-level metadata: exactly one row.
CREATE TABLE store_meta (
    id              INTEGER PRIMARY KEY CHECK (id = 1),
    format          TEXT    NOT NULL DEFAULT 'pimdir' CHECK (typeof(format) = 'text'),
    -- The version of STORAGE.md whose schema the store holds (§4.2): the
    -- draft's own name while it is a draft, storage-vN once released. A
    -- program opens a draft's store only under that exact draft.
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
    -- until an engine writes, then its own, the draft's name while SYNC.md is
    -- a draft and sync-vN once released. An engine refuses a version it does
    -- not implement (SYNC.md §10).
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
    -- instant at seconds precision, as mail_summary.date (§13).
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
-- A hash is a name, never a path: the BLAKE3 digest as 52 characters of
-- lowercase base32 (§5), so no row, and through the foreign keys onto it no
-- pointer and no queued body, names `..`, a separator or anything else a path
-- could be built from.
--
-- The refcount floor is load-bearing rather than tidy: a double release either
-- fails every later write on a foreign key that names neither the object nor
-- the miscount, or goes unnoticed entirely. The CHECK moves the failure to the
-- statement that caused it (§7).
CREATE TABLE objects (
    hash     TEXT PRIMARY KEY CHECK (typeof(hash) = 'text')
             CHECK (length(hash) = 52 AND hash NOT GLOB '*[^a-z2-7]*'),
    size     INTEGER NOT NULL CHECK (typeof(size) = 'integer') CHECK (size >= 0),  -- body length in bytes
    refcount INTEGER NOT NULL DEFAULT 0 CHECK (typeof(refcount) = 'integer') CHECK (refcount >= 0)
);

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
-- What the item says about itself is its kind's summary row (§4.4).
--
-- `id` is the placement's own key, which every child of it carries: never
-- reused (AUTOINCREMENT) and never shown, a consumer keeping (collection,
-- seq) and a writer (collection, link_id), the key the store files it under.
CREATE TABLE items (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    collection      TEXT NOT NULL CHECK (typeof(collection) = 'text') REFERENCES collections(id) ON UPDATE CASCADE ON DELETE CASCADE,
    link_id         TEXT NOT NULL CHECK (typeof(link_id) = 'text') CHECK (link_id != ''),  -- never empty; the key the item is filed under: the identity hint, escaped as esc:<hint> when it begins like a derived key, a kind fallback, or a minted dup:<hint>#<handle> (§9)
    seq             INTEGER NOT NULL CHECK (typeof(seq) = 'integer') CHECK (seq >= 1),  -- public id, shared by every placement of the link id (§9.1)
    -- Whether the flag set is known: 1 its placement_flag rows are the set,
    -- none being known-empty; 0 unknown, and then it holds no row.
    flags_known     INTEGER NOT NULL DEFAULT 0 CHECK (typeof(flags_known) = 'integer') CHECK (flags_known IN (0, 1)),
    -- The system flags of the set (§13), by their exact bytes: \Seen 1,
    -- \Answered 2, \Flagged 4, \Draft 8, \Deleted 16; every other flag is a
    -- placement_flag row. 0 while the set is unknown.
    marks           INTEGER NOT NULL DEFAULT 0 CHECK (typeof(marks) = 'integer') CHECK (marks BETWEEN 0 AND 31),
    object_hash     TEXT CHECK (typeof(object_hash) IN ('text', 'null')) REFERENCES objects(hash),  -- current body, NULL until hydrated
    sort_key        TEXT NOT NULL DEFAULT '' CHECK (typeof(sort_key) = 'text'),  -- the kind's ordering key, '' when unknown (§9.3)
    -- The detail ladder: 1 meta, 2 full (§13).
    level           INTEGER NOT NULL CHECK (typeof(level) = 'integer') CHECK (level IN (1, 2)),
    deleted         INTEGER NOT NULL DEFAULT 0 CHECK (typeof(deleted) = 'integer') CHECK (deleted IN (0, 1)),  -- 1 while a delete propagates across sources
    retained_at     TEXT CHECK (typeof(retained_at) IN ('text', 'null'))  -- the instant the last binding vanished (§11), the shape of §13
                    CHECK (retained_at GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9].[0-9][0-9][0-9]Z'),
    retained_by     TEXT CHECK (typeof(retained_by) IN ('text', 'null')),  -- the source whose removal retired it, diagnostic
    conflicted      INTEGER NOT NULL DEFAULT 0 CHECK (typeof(conflicted) = 'integer') CHECK (conflicted IN (0, 1)),  -- 1 while a cross-source content conflict is unresolved
    conflict_object TEXT CHECK (typeof(conflict_object) IN ('text', 'null')) REFERENCES objects(hash),  -- the diverging body a manual conflict recorded
    changed         INTEGER NOT NULL DEFAULT 0 CHECK (typeof(changed) = 'integer'),  -- the change stamp (§4.5), trigger-maintained
    UNIQUE (collection, link_id),
    -- What a binding's foreign key names, so its collection is its item's.
    UNIQUE (id, collection),
    -- The terminal states §11 and §10 describe, held by the schema.
    CHECK (retained_at IS NULL OR deleted = 1),
    CHECK (retained_by IS NULL OR retained_at IS NOT NULL),
    CHECK (conflicted = 1 OR conflict_object IS NULL),
    CHECK (flags_known = 1 OR marks = 0)
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
CREATE INDEX items_by_retained ON items(retained_at, object_hash) WHERE retained_at IS NOT NULL;
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
    flags_known, marks, object_hash, sort_key, level, deleted, retained_at, conflicted, conflict_object
ON items
WHEN OLD.flags_known IS NOT NEW.flags_known
  OR OLD.marks IS NOT NEW.marks
  OR OLD.object_hash IS NOT NEW.object_hash
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

-- A placement's flags other than the system flags items.marks holds (§13),
-- one row per flag, while items.flags_known is 1. A flag is printable and
-- holds no space, so a reader joins a set with spaces and splits it back
-- (§14.1). The flag index answers a flag predicate by a seek rather than a
-- scan of every placement.
CREATE TABLE placement_flag (
    item INTEGER NOT NULL CHECK (typeof(item) = 'integer') REFERENCES items(id) ON DELETE CASCADE,
    flag TEXT    NOT NULL CHECK (typeof(flag) = 'text') CHECK (flag != '' AND flag NOT GLOB '*[^!-~]*'),
    PRIMARY KEY (item, flag)
) WITHOUT ROWID;

CREATE INDEX placement_flag_by_flag ON placement_flag(flag);

-- An unknown set holds no row: a flag written under it fails here, and a set
-- becoming unknown loses its rows.
CREATE TRIGGER placement_flag_needs_known BEFORE INSERT ON placement_flag
WHEN (SELECT flags_known FROM items WHERE id = NEW.item) IS NOT 1
BEGIN
    SELECT RAISE(ABORT, 'flags unknown');
END;

CREATE TRIGGER items_forget_flags AFTER UPDATE OF flags_known ON items
WHEN NEW.flags_known = 0
BEGIN
    DELETE FROM placement_flag WHERE item = NEW.id;
END;

-- A flag added or removed requests the placement's stamp (§4.5), so a set
-- written again as it was, which moves no row, stamps nothing.
CREATE TRIGGER placement_flag_stamp_insert AFTER INSERT ON placement_flag
BEGIN
    UPDATE items SET changed = -1 WHERE id = NEW.item;
END;

CREATE TRIGGER placement_flag_stamp_delete AFTER DELETE ON placement_flag
BEGIN
    UPDATE items SET changed = -1 WHERE id = OLD.item;
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
    -- item's: 1 base_marks and its binding_base_flag rows are the set, 0
    -- unknown.
    base_flags_known  INTEGER NOT NULL DEFAULT 0 CHECK (typeof(base_flags_known) = 'integer') CHECK (base_flags_known IN (0, 1)),
    -- The base's system flags, as items.marks holds the item's (§13).
    base_marks        INTEGER NOT NULL DEFAULT 0 CHECK (typeof(base_marks) = 'integer') CHECK (base_marks BETWEEN 0 AND 31),
    base_object       TEXT CHECK (typeof(base_object) IN ('text', 'null')) REFERENCES objects(hash),
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
    conflict_object   TEXT CHECK (typeof(conflict_object) IN ('text', 'null')) REFERENCES objects(hash),
    -- The shared body this source last reconciled against, the base of the
    -- cross-source merge (§10, §13). base_object answers to the source's own
    -- remote and only a sync moves it, so a body this source folded in and has
    -- not pushed yet leaves it behind; read as the shared base it would have
    -- the source disagree with itself. Meaningful whether or not the binding
    -- is conflicted. Pinned like the base (§5): it is the common ancestor a
    -- merge reads, one body per binding, released when the binding next agrees.
    shared_object     TEXT CHECK (typeof(shared_object) IN ('text', 'null')) REFERENCES objects(hash),
    -- The id of the last round whose listing carried this handle (SYNC.md
    -- §5), NULL until one did: a round's last page drops the in-scope
    -- bindings it did not stamp.
    round             INTEGER CHECK (typeof(round) IN ('integer', 'null')),
    PRIMARY KEY (item, source),
    -- A binding that is not conflicted carries neither (§13).
    CHECK (conflicted = 1 OR (conflict_revision IS NULL AND conflict_object IS NULL)),
    CHECK (base_flags_known = 1 OR base_marks = 0),
    CHECK (base_present = 1 OR (base_flags_known = 0 AND base_object IS NULL AND base_revision IS NULL)),
    -- ON UPDATE as well as ON DELETE: renaming a collection cascades into
    -- items.collection, so its bindings follow it (§14).
    FOREIGN KEY (item, collection) REFERENCES items(id, collection) ON UPDATE CASCADE ON DELETE CASCADE
);

-- A binding's base flags other than its base_marks (§13), one row per flag,
-- while bindings.base_flags_known is 1, spelled as placement_flag's. A base
-- carries no stamp, so its writes draw none.
CREATE TABLE binding_base_flag (
    item   INTEGER NOT NULL CHECK (typeof(item) = 'integer'),
    source TEXT    NOT NULL CHECK (typeof(source) = 'text'),
    flag   TEXT    NOT NULL CHECK (typeof(flag) = 'text') CHECK (flag != '' AND flag NOT GLOB '*[^!-~]*'),
    PRIMARY KEY (item, source, flag),
    FOREIGN KEY (item, source) REFERENCES bindings(item, source) ON DELETE CASCADE
) WITHOUT ROWID;

CREATE TRIGGER binding_base_flag_needs_known BEFORE INSERT ON binding_base_flag
WHEN (SELECT base_flags_known FROM bindings WHERE item = NEW.item AND source = NEW.source) IS NOT 1
BEGIN
    SELECT RAISE(ABORT, 'base flags unknown');
END;

CREATE TRIGGER bindings_forget_base_flags AFTER UPDATE OF base_flags_known ON bindings
WHEN NEW.base_flags_known = 0
BEGIN
    DELETE FROM binding_base_flag WHERE item = NEW.item AND source = NEW.source;
END;

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

-- The summaries (§4.4, Annex A): what a reader lists an item from without
-- its body, one table per kind, at most one row per item, cascading with it.
-- Written by the item's writer under Annex A; none references an object.

-- message/rfc822 (Annex A.1). Every address is also an item_address row.
CREATE TABLE mail_summary (
    item INTEGER PRIMARY KEY REFERENCES items(id) ON DELETE CASCADE,
    message_id   TEXT CHECK (typeof(message_id) IN ('text', 'null')),  -- bare Message-ID, angle brackets stripped
    subject      TEXT NOT NULL CHECK (typeof(subject) = 'text'),  -- decoded (RFC 2047), may be empty
    sender       TEXT CHECK (typeof(sender) IN ('text', 'null')),  -- first From address, canonical (Annex A.6)
    sender_name  TEXT CHECK (typeof(sender_name) IN ('text', 'null')),  -- its display name, decoded, or NULL
    date         TEXT CHECK (typeof(date) IN ('text', 'null')),  -- RFC 3339 UTC Z at seconds precision, or NULL
    size         INTEGER CHECK (typeof(size) IN ('integer', 'null')) CHECK (size >= 0),  -- the body's octets, else the source's figure (Annex A.1), or NULL
    attachment   INTEGER CHECK (typeof(attachment) IN ('integer', 'null')) CHECK (attachment IN (0, 1)),  -- 1 has one, 0 has none, NULL not examined
    invitation   TEXT CHECK (typeof(invitation) IN ('text', 'null'))  -- the UID its first text/calendar part carries, NULL none or not examined
);

-- The mail inviting to a calendar item, for link_invitations_to (§14.2).
-- Partial: most mail invites to nothing.
CREATE INDEX mail_summary_by_invitation ON mail_summary(invitation) WHERE invitation IS NOT NULL;

-- A message's In-Reply-To ids (Annex A.1), bare, `position` their 0-based
-- document order. By id, for list_replied.
CREATE TABLE mail_in_reply_to (
    item       INTEGER NOT NULL CHECK (typeof(item) = 'integer') REFERENCES mail_summary(item) ON DELETE CASCADE,
    position   INTEGER NOT NULL CHECK (typeof(position) = 'integer'),
    message_id TEXT    NOT NULL CHECK (typeof(message_id) = 'text'),
    PRIMARY KEY (item, position)
) WITHOUT ROWID;

CREATE INDEX mail_in_reply_to_by_id ON mail_in_reply_to(message_id);

-- text/vcard (Annex A.2). Every EMAIL is an item_address row.
CREATE TABLE contact_summary (
    item INTEGER PRIMARY KEY REFERENCES items(id) ON DELETE CASCADE,
    uid        TEXT CHECK (typeof(uid) IN ('text', 'null')),  -- the UID verbatim
    fn         TEXT NOT NULL CHECK (typeof(fn) = 'text'),  -- FN decoded (Annex A.2), '' when absent
    kind       TEXT CHECK (typeof(kind) IN ('text', 'null')),  -- KIND lowercased: individual, group, org, location; NULL when absent
    org        TEXT CHECK (typeof(org) IN ('text', 'null'))  -- first ORG component, unescaped, or NULL
);

-- text/calendar, one table per component (Annex A.3 to A.5): a resource is
-- one VEVENT, VTODO or VJOURNAL set. A start is carried verbatim with its
-- parameters; the one resolved instant is items.sort_key.
CREATE TABLE event_summary (
    item INTEGER PRIMARY KEY REFERENCES items(id) ON DELETE CASCADE,
    uid           TEXT CHECK (typeof(uid) IN ('text', 'null')),  -- the UID verbatim
    summary       TEXT NOT NULL CHECK (typeof(summary) = 'text'),  -- SUMMARY unescaped, may be empty
    location      TEXT CHECK (typeof(location) IN ('text', 'null')),  -- LOCATION unescaped, or NULL
    dtstart       TEXT CHECK (typeof(dtstart) IN ('text', 'null')),  -- the value verbatim
    dtstart_tzid  TEXT CHECK (typeof(dtstart_tzid) IN ('text', 'null')),  -- the TZID parameter, or NULL
    dtstart_value TEXT CHECK (typeof(dtstart_value) IN ('text', 'null')),  -- 'date-time' or 'date'
    dtend         TEXT CHECK (typeof(dtend) IN ('text', 'null')),  -- the value verbatim, or NULL
    recurring     INTEGER CHECK (typeof(recurring) IN ('integer', 'null')) CHECK (recurring IN (0, 1)),  -- 1 carries an RRULE or RDATE, 0 none, NULL not examined
    until         TEXT CHECK (typeof(until) IN ('text', 'null'))  -- the RRULE's UNTIL verbatim, or NULL
);

CREATE TABLE task_summary (
    item INTEGER PRIMARY KEY REFERENCES items(id) ON DELETE CASCADE,
    uid           TEXT CHECK (typeof(uid) IN ('text', 'null')),
    summary       TEXT NOT NULL CHECK (typeof(summary) = 'text'),
    dtstart       TEXT CHECK (typeof(dtstart) IN ('text', 'null')),
    dtstart_tzid  TEXT CHECK (typeof(dtstart_tzid) IN ('text', 'null')),
    dtstart_value TEXT CHECK (typeof(dtstart_value) IN ('text', 'null')),
    due           TEXT CHECK (typeof(due) IN ('text', 'null')),  -- the DUE value verbatim, or NULL
    due_tzid      TEXT CHECK (typeof(due_tzid) IN ('text', 'null')),
    due_value     TEXT CHECK (typeof(due_value) IN ('text', 'null')),
    status        TEXT CHECK (typeof(status) IN ('text', 'null')),  -- STATUS uppercased verbatim, or NULL
    completed     TEXT CHECK (typeof(completed) IN ('text', 'null')),  -- COMPLETED verbatim (always UTC per RFC 5545), or NULL
    percent       INTEGER CHECK (typeof(percent) IN ('integer', 'null')),  -- PERCENT-COMPLETE, or NULL
    recurring     INTEGER CHECK (typeof(recurring) IN ('integer', 'null')) CHECK (recurring IN (0, 1)),
    until         TEXT CHECK (typeof(until) IN ('text', 'null')),
    priority      INTEGER CHECK (typeof(priority) IN ('integer', 'null')) CHECK (priority BETWEEN 0 AND 9),  -- PRIORITY, or NULL
    parent        TEXT CHECK (typeof(parent) IN ('text', 'null')),  -- the UID the first parent RELATED-TO names, or NULL
    mid           TEXT CHECK (typeof(mid) IN ('text', 'null')),  -- the Message-ID the first mid: URI names, bare, or NULL
    created       TEXT CHECK (typeof(created) IN ('text', 'null'))  -- CREATED, else DTSTAMP, as an instant (Annex A.4), or NULL
);

-- The tasks naming a calendar item their parent, and those naming a mail, for
-- link_parents_to and link_sources_to (§14.2). Partial: most tasks name
-- neither.
CREATE INDEX task_summary_by_parent ON task_summary(parent) WHERE parent IS NOT NULL;
CREATE INDEX task_summary_by_mid ON task_summary(mid) WHERE mid IS NOT NULL;

-- A task's CATEGORIES values (Annex A.4), decoded, `position` their 0-based
-- document order.
CREATE TABLE task_category (
    item       INTEGER NOT NULL CHECK (typeof(item) = 'integer') REFERENCES task_summary(item) ON DELETE CASCADE,
    position   INTEGER NOT NULL CHECK (typeof(position) = 'integer'),
    value      TEXT    NOT NULL CHECK (typeof(value) = 'text'),
    PRIMARY KEY (item, position)
) WITHOUT ROWID;

CREATE TABLE journal_summary (
    item INTEGER PRIMARY KEY REFERENCES items(id) ON DELETE CASCADE,
    uid           TEXT CHECK (typeof(uid) IN ('text', 'null')),
    summary       TEXT NOT NULL CHECK (typeof(summary) = 'text'),
    dtstart       TEXT CHECK (typeof(dtstart) IN ('text', 'null')),
    dtstart_tzid  TEXT CHECK (typeof(dtstart_tzid) IN ('text', 'null')),
    dtstart_value TEXT CHECK (typeof(dtstart_value) IN ('text', 'null'))
);

-- application/octet-stream, a file (Annex A.7): what its source or its writer
-- states, the bytes saying nothing of it. One row per placement, so a file
-- in two folders may carry two names. `part` stays with the file wherever it
-- is placed.
CREATE TABLE file_summary (
    item INTEGER PRIMARY KEY REFERENCES items(id) ON DELETE CASCADE,
    name       TEXT NOT NULL CHECK (typeof(name) = 'text'),  -- the file's name in this collection, may be empty
    media_type TEXT CHECK (typeof(media_type) IN ('text', 'null')),  -- type/subtype lowercased, no parameter, or NULL
    size       INTEGER CHECK (typeof(size) IN ('integer', 'null')) CHECK (size >= 0),  -- octets: the body's when held, else as stated
    part       TEXT CHECK (typeof(part) IN ('text', 'null'))  -- an attachment's IMAP section in its message, or NULL
);

-- The people an item names, whatever its kind (§4.4, Annex A.6). One generic
-- table, since "everything about this address" is asked across every kind.
CREATE TABLE item_address (
    item       INTEGER NOT NULL CHECK (typeof(item) = 'integer') REFERENCES items(id) ON DELETE CASCADE,
    role       TEXT NOT NULL CHECK (typeof(role) = 'text'),  -- from, to, cc, bcc, email, organizer, attendee, contact (§13)
    position   INTEGER NOT NULL CHECK (typeof(position) = 'integer'),  -- 0-based document order within the role
    address    TEXT NOT NULL CHECK (typeof(address) = 'text'),  -- canonical addr-spec (§13)
    name       TEXT CHECK (typeof(name) IN ('text', 'null')),  -- display name, decoded, or NULL
    PRIMARY KEY (item, role, position)
) WITHOUT ROWID;

-- The person axis: every placement naming one address, by role. The table has
-- no rowid, so the index carries the rest of its key and names each placement
-- without reading the row.
CREATE INDEX item_address_by_address ON item_address(address, role);

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
      AND +object_hash IS NULL
      AND (SELECT kind FROM collections c WHERE c.id = items.collection) = 'application/octet-stream'
      AND NOT EXISTS (SELECT 1 FROM bindings b WHERE b.item = items.id)
      AND NOT EXISTS (SELECT 1 FROM item_reference r
                      WHERE (r.from_link_id = items.link_id AND r.from_kind = 'application/octet-stream')
                         OR (r.to_link_id = items.link_id AND r.to_kind = 'application/octet-stream'));
END;

-- The action queue (§15): mutations requested by processes that do not own the
-- store, applied by the owner in append order.
CREATE TABLE queue (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,  -- global append order
    created_at  TEXT    NOT NULL CHECK (typeof(created_at) = 'text')  -- stamped by SQLite, the shape of §13
                CHECK (created_at GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9].[0-9][0-9][0-9]Z'),
    producer    TEXT    NOT NULL CHECK (typeof(producer) = 'text'),  -- enqueuing process, diagnostic
    collection  TEXT    NOT NULL CHECK (typeof(collection) = 'text') REFERENCES collections(id) ON UPDATE CASCADE ON DELETE CASCADE,
    action      TEXT    NOT NULL CHECK (typeof(action) = 'text'),  -- 'add' | 'set-flags' | 'remove' | 'move' | 'copy' | 'update' | 'set-performer' | an intent (§15.3, Annex B)
    payload     TEXT    NOT NULL CHECK (typeof(payload) = 'text'),  -- versioned JSON, shape per action (§15)
    -- The collection a `move` or a `copy` targets, or the one holding the item
    -- a superseding `add` replaces (§15.3): written beside the payload, so a
    -- rename follows it, and read in place of the payload's own.
    target_collection TEXT CHECK (typeof(target_collection) IN ('text', 'null')),
    object_hash TEXT CHECK (typeof(object_hash) IN ('text', 'null')) REFERENCES objects(hash),  -- pins the payload's body against the collector, or NULL
    attempts    INTEGER NOT NULL DEFAULT 0 CHECK (typeof(attempts) = 'integer') CHECK (attempts >= 0),
    error       TEXT CHECK (typeof(error) IN ('text', 'null'))  -- last failure; non-NULL means parked
);

-- What became of an applied action (§15.2, §15.4), keyed by the queue row's id:
-- application deletes the row, so a producer holding the id its enqueue
-- answered reads here that the row was applied and, for an `add`, the seq of
-- the item it created. Written by the owner in the transaction applying the
-- row, kept at least seven days, then pruned (prune_receipts). A cancelled row
-- leaves none. `seq` names no foreign key: a later move or purge retires the
-- item, and the receipt still says what the add created.
CREATE TABLE receipts (
    id         INTEGER PRIMARY KEY,        -- the applied queue row's id
    applied_at TEXT    NOT NULL CHECK (typeof(applied_at) = 'text')  -- stamped by SQLite, the shape of §13
               CHECK (applied_at GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9].[0-9][0-9][0-9]Z'),
    -- The collection the row was queued on, following its rename; NULL once
    -- that collection is gone, a `collection-delete` applied included, so the
    -- receipt outlives it and the intent never reads as withdrawn.
    collection TEXT    CHECK (typeof(collection) IN ('text', 'null')) REFERENCES collections(id) ON UPDATE CASCADE ON DELETE SET NULL,
    seq        INTEGER CHECK (typeof(seq) IN ('integer', 'null')) CHECK (seq >= 1)  -- the item an `add` created, else NULL
);

-- A reader overlays a collection's pending actions (§15.4).
CREATE INDEX queue_by_collection ON queue(collection, id);
-- The owner's drain, store-wide in append order, skipping the parked rows
-- (§15.2). Partial, so it holds only what is pending.
CREATE INDEX queue_pending ON queue(id) WHERE error IS NULL;

-- A collection holding a pending or parked action is not deleted (§14): the
-- cascade would drop the action, an intent included, with no receipt and no
-- report. The operator cancels or lets the drain apply each row first.
CREATE TRIGGER collections_keep_queued BEFORE DELETE ON collections
WHEN EXISTS (SELECT 1 FROM queue WHERE collection = OLD.id)
BEGIN
    SELECT RAISE(ABORT, 'collection holds queued actions');
END;

-- Cross-source identity lookup (dedup, thread stitching) and refcount
-- navigation. A pointer index is partial on the pointer being set: most rows
-- point at nothing, an equality implies the pointer is set, and so the foreign
-- key check of an object's delete seeks it as it would the whole index.
CREATE INDEX items_by_object ON items(object_hash) WHERE object_hash IS NOT NULL;
-- The other side of items_by_object: each collection's live rows holding no
-- body, which the search part's coverage counts per collection (SEARCH.md
-- §8.2) by a seek. Partial, so a fully synced collection adds nothing, and
-- covering, the two columns it is partial on costing a byte each.
CREATE INDEX items_bodiless ON items(collection, deleted, object_hash) WHERE object_hash IS NULL AND deleted = 0;
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
CREATE INDEX queue_by_object ON queue(object_hash) WHERE object_hash IS NOT NULL;
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
