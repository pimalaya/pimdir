-- pimdir store schema, version 1. Section references are to STORAGE.md.
--
-- Applied by a migration runner (§6) against an empty database, inside a
-- transaction; the runner sets `PRAGMA user_version = 1` on success. Pure DDL,
-- so every implementation applies the identical bytes. Requires SQLite >= 3.37
-- for STRICT tables and DROP COLUMN.

-- Store-level metadata: exactly one row.
CREATE TABLE store_meta (
    id          INTEGER PRIMARY KEY CHECK (id = 1),
    format      TEXT    NOT NULL DEFAULT 'pimdir',
    version     INTEGER NOT NULL,           -- tracks user_version
    hash_algo   TEXT    NOT NULL,           -- 'blake3' (default) or 'sha256-128'
    created_at  TEXT    NOT NULL,           -- RFC 3339, Z (§13)
    -- Hands out the next item `seq`; only ever increases, so a public id is
    -- never reused store-wide (§9.1).
    next_seq    INTEGER NOT NULL DEFAULT 1,
    -- The next change stamp (§4.5), drawn by the triggers below; a consumer
    -- records next_change - 1, the last stamp drawn.
    next_change INTEGER NOT NULL DEFAULT 1,
    -- Rows that left without a stamp (§4.5): purged items and collected
    -- objects, counted by the delete triggers below.
    purges      INTEGER NOT NULL DEFAULT 0
) STRICT;

-- Collections: mailboxes, address books, calendars. Hierarchy is by `parent`,
-- never by nesting rows.
--
-- `account` groups collections and partitions no identifier (§9.2). `id` stays
-- unique store-wide, so an owner holding two accounts namespaces their ids
-- itself (`work/INBOX`, `home/INBOX`) and records the grouping in this column
-- rather than leaving readers to parse it back out.
CREATE TABLE collections (
    id          TEXT PRIMARY KEY,          -- stable id (base32 uuid or backend id), unique store-wide
    account     TEXT,                      -- owning account, NULL in a single-account store
    kind        TEXT NOT NULL,             -- media type: message/rfc822, text/vcard, text/calendar
    name        TEXT NOT NULL,             -- logical name (INBOX, Contacts)
    parent      TEXT REFERENCES collections(id) ON UPDATE CASCADE ON DELETE SET NULL,
    color       TEXT,                      -- optional presentation
    description TEXT,
    sort_order  INTEGER,
    conflict    TEXT NOT NULL DEFAULT 'manual'
                CHECK (conflict IN ('manual', 'prefer-incoming', 'prefer-existing')),
    -- What the source says the collection is for (§14), NULL when it says
    -- nothing: a mail role is the JMAP Mailbox/role vocabulary (the IANA IMAP
    -- mailbox name attributes lowercased, plus inbox), and `default` marks the
    -- calendar or address book a source writes to when none is named.
    role        TEXT CHECK (role IS NULL
                OR (kind = 'message/rfc822' AND role IN ('inbox', 'sent', 'drafts', 'trash',
                    'junk', 'archive', 'all', 'flagged', 'important'))
                OR (kind IN ('text/calendar', 'text/vcard') AND role = 'default')),
    -- Handle-space epoch, bumped by the owner on a backend identity reset, so a
    -- reader derives an IMAP UIDVALIDITY from the store alone (§12).
    generation  INTEGER NOT NULL DEFAULT 1,
    -- The change stamp (§4.5), maintained by the triggers below.
    changed     INTEGER NOT NULL DEFAULT 0
) STRICT;

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
-- consumer keyed on the old id drops them and never learns the new one.
CREATE TRIGGER collections_restamp_items AFTER UPDATE OF id ON collections
WHEN OLD.id IS NOT NEW.id
BEGIN
    UPDATE items SET changed = -1 WHERE collection IN (OLD.id, NEW.id);
END;

-- One row per source syncing a collection (a server, a phone): its sync
-- cursor, the coverage that cursor serves, and the round under way (SYNC.md
-- §5). A scope is `[since, until)` on the mail summary's `date`, NULL bounds
-- open; the coverage is the scope of the last round that closed, and the
-- store is complete over it.
CREATE TABLE sources (
    collection       TEXT NOT NULL REFERENCES collections(id) ON UPDATE CASCADE ON DELETE CASCADE,
    source           TEXT NOT NULL,        -- source id ('left', 'right', 'phone')
    checkpoint       BLOB,                 -- opaque remote cursor (QRESYNC/JMAP state, DAV sync-token)
    covered_since    TEXT,                 -- the coverage's floor, RFC 3339 Z, NULL unbounded
    covered_until    TEXT,                 -- its ceiling, exclusive, NULL unbounded
    -- When the last round closed, stamped by SQLite; NULL is never complete,
    -- and then the coverage carries no bound.
    covered_at       TEXT CHECK (covered_at IS NOT NULL OR (covered_since IS NULL AND covered_until IS NULL)),
    -- The last round id drawn (open_round), so a restarted round stamps
    -- afresh and a binding's stamp names one listing.
    round            INTEGER NOT NULL DEFAULT 0,
    round_since      TEXT,                 -- the open round's scope, NULL bounds open
    round_until      TEXT,
    round_cursor     BLOB,                 -- the connector's resume cursor, opaque
    round_checkpoint BLOB,                 -- the checkpoint the round lands when it closes
    -- When the open round began, stamped by SQLite; NULL is no round open,
    -- and then it carries nothing.
    round_started_at TEXT CHECK (round_started_at IS NOT NULL OR (round_since IS NULL AND
                     round_until IS NULL AND round_cursor IS NULL AND round_checkpoint IS NULL)),
    -- Whether the open round lists only the band its coverage lacks, whose
    -- absence infers no delete of an undated member; 0 with no round open.
    round_band       INTEGER NOT NULL DEFAULT 0 CHECK (round_band = 0 OR (round_band = 1 AND round_started_at IS NOT NULL)),
    PRIMARY KEY (collection, source)
) STRICT;

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
-- source syncs, `none` included, so a source with no row is undeclared, the
-- state of a store from an owner predating §15.6, and gated by nothing. A row
-- naming a collection overrides the source's row there (a read-only calendar
-- in a writable account); NULL is the source-wide row, so the key is an
-- expression index. A source id names one remote store-wide; `account` is the
-- one it syncs for, NULL in a single-account store, so a source is a candidate
-- for its account's intents before it has synced a collection.
CREATE TABLE capabilities (
    account    TEXT,
    source     TEXT NOT NULL,
    collection TEXT REFERENCES collections(id) ON UPDATE CASCADE ON DELETE CASCADE,
    capability TEXT NOT NULL,              -- Annex B name, or an `x-` one
    support    TEXT NOT NULL CHECK (support IN ('full', 'partial', 'none')),
    detail     TEXT                        -- what is missing or why, for a human
) STRICT;

CREATE UNIQUE INDEX capabilities_key ON capabilities(source, ifnull(collection, ''), capability);

-- The source the user chose to perform an intent capability when several of
-- an account's sources declare it (§15.6), written by the owner applying a
-- `set-performer` action. `account` is NULL in a single-account store, so the
-- key is an expression index rather than a primary key.
CREATE TABLE performers (
    account    TEXT,
    capability TEXT NOT NULL,
    source     TEXT NOT NULL
) STRICT;

CREATE UNIQUE INDEX performers_key ON performers(ifnull(account, ''), capability);

-- Content-addressed body index; the bytes live in blob files (§5).
--
-- The refcount floor is load-bearing rather than tidy: a double release either
-- fails every later write on a foreign key that names neither the object nor
-- the miscount, or goes unnoticed entirely. The CHECK moves the failure to the
-- statement that caused it (§7).
CREATE TABLE objects (
    hash     TEXT PRIMARY KEY,             -- content hash under store_meta.hash_algo, base32
    size     INTEGER NOT NULL,             -- body length in bytes
    refcount INTEGER NOT NULL DEFAULT 0 CHECK (refcount >= 0)
) STRICT;

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
CREATE TABLE items (
    collection      TEXT NOT NULL REFERENCES collections(id) ON UPDATE CASCADE ON DELETE CASCADE,
    link_id         TEXT NOT NULL,         -- the key the item is filed under: the identity hint, a kind fallback, or a minted dup:<hint>#<handle> (§9)
    seq             INTEGER NOT NULL,      -- public id, shared by every placement of the link id (§9.1)
    flags           TEXT CHECK (flags IS NULL OR json_valid(flags)),  -- JSON array of flag strings
    object_hash     TEXT REFERENCES objects(hash),  -- current body, NULL until hydrated
    sort_key        TEXT NOT NULL DEFAULT '',  -- the kind's ordering key, '' when unknown (§9.3)
    -- The detail ladder: 1 meta, 2 full. 0 is what an earlier draft wrote for a
    -- probed or pulled row, never written now and read as 1 (§13).
    level           INTEGER NOT NULL CHECK (level IN (0, 1, 2)),
    deleted         INTEGER NOT NULL DEFAULT 0 CHECK (deleted IN (0, 1)),  -- 1 while a delete propagates across sources
    retained_at     TEXT,                  -- RFC 3339 instant the last binding vanished (§11)
    retained_by     TEXT,                  -- the source whose removal retired it, diagnostic
    conflicted      INTEGER NOT NULL DEFAULT 0 CHECK (conflicted IN (0, 1)),  -- 1 while a cross-source content conflict is unresolved
    conflict_object TEXT REFERENCES objects(hash),  -- the diverging body a manual conflict recorded
    changed         INTEGER NOT NULL DEFAULT 0,     -- the change stamp (§4.5), trigger-maintained
    PRIMARY KEY (collection, link_id),
    -- The terminal states §11 and §10 describe, held by the schema.
    CHECK (retained_at IS NULL OR deleted = 1),
    CHECK (conflicted = 1 OR conflict_object IS NULL)
) STRICT;

-- Resolves a public id back to the internal link id.
CREATE UNIQUE INDEX items_by_seq ON items(collection, seq);
-- "Does this link id already have a seq?", which is what makes every placement
-- share one, and list_link_placements (§9.2).
CREATE INDEX items_by_link ON items(link_id);
-- The trash view (§11, §14.1): every deleted row, retained or still
-- propagating. It leads with `seq` because the listing pages on the public
-- id: ordering by anything else sorts every such row to return one page.
CREATE INDEX items_retained ON items(collection, seq) WHERE deleted = 1;
-- Orders a collection by the kind's own key, `seq` breaking the tie so a keyset
-- page over a non-unique key is total. Partial on the live rows, which every
-- listing filters on, so a mailbox whose server expunged most of it does not
-- page past its own trash (§14.1).
CREATE INDEX items_by_sort ON items(collection, sort_key, seq) WHERE deleted = 0;
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
    WHERE collection = NEW.collection AND link_id = NEW.link_id;
    UPDATE store_meta SET next_change = next_change + 1 WHERE id = 1;
END;

CREATE TRIGGER items_stamp_update AFTER UPDATE OF
    flags, object_hash, sort_key, level, deleted, retained_at, conflicted, conflict_object
ON items
WHEN OLD.flags IS NOT NEW.flags
  OR OLD.object_hash IS NOT NEW.object_hash
  OR OLD.sort_key IS NOT NEW.sort_key
  OR OLD.level IS NOT NEW.level
  OR OLD.deleted IS NOT NEW.deleted
  OR OLD.retained_at IS NOT NEW.retained_at
  OR OLD.conflicted IS NOT NEW.conflicted
  OR OLD.conflict_object IS NOT NEW.conflict_object
BEGIN
    UPDATE items SET changed = (SELECT next_change FROM store_meta WHERE id = 1)
    WHERE collection = NEW.collection AND link_id = NEW.link_id;
    UPDATE store_meta SET next_change = next_change + 1 WHERE id = 1;
END;

CREATE TRIGGER items_stamp_request AFTER UPDATE OF changed ON items
WHEN NEW.changed = -1
BEGIN
    UPDATE items SET changed = (SELECT next_change FROM store_meta WHERE id = 1)
    WHERE collection = NEW.collection AND link_id = NEW.link_id;
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
    collection        TEXT NOT NULL,
    link_id           TEXT NOT NULL,
    source            TEXT NOT NULL,
    -- The item's backend id on this source (IMAP UID, DAV href). Bound once:
    -- a write resolving this binding to another handle is refused, and the one
    -- licensed rebind is the handle-space rebuild (§10, §12).
    handle            TEXT NOT NULL,
    base_flags        TEXT CHECK (base_flags IS NULL OR json_valid(base_flags)),  -- JSON array of strings, or NULL
    base_object       TEXT REFERENCES objects(hash),
    base_revision     TEXT,                -- etag/modseq for mutable-content backends
    -- Whether a base exists at all, which its three value columns cannot say: a
    -- source reporting no revision, no body and no flags still agreed, and that
    -- agreement is what tells a pending push from a settled one (§13).
    base_present      INTEGER NOT NULL DEFAULT 0 CHECK (base_present IN (0, 1)),
    -- This source diverged from its OWN remote (§10), unlike items.conflicted,
    -- which is the cross-source divergence.
    conflicted        INTEGER NOT NULL DEFAULT 0 CHECK (conflicted IN (0, 1)),
    conflict_revision TEXT,                -- the remote revision observed when it did, or NULL
    -- The diverging remote body at that revision, so a resolver reads base,
    -- local and remote from the store and needs no credentials (§13). Pinned
    -- like any other reference while the binding stays conflicted.
    conflict_object   TEXT REFERENCES objects(hash),
    -- The shared body this source last reconciled against, the base of the
    -- cross-source merge (§10, §13). base_object answers to the source's own
    -- remote and only a sync moves it, so a body this source folded in and has
    -- not pushed yet leaves it behind; read as the shared base it would have
    -- the source disagree with itself. Meaningful whether or not the binding
    -- is conflicted. It names an object and pins none, hence no REFERENCES and
    -- no refcount: the value is only ever compared for equality, never read as
    -- bytes, and a content hash compares the same after the body it named has
    -- been swept.
    shared_object     TEXT,
    -- The id of the last round whose listing carried this handle (SYNC.md
    -- §5), NULL until one did: a round's last page drops the in-scope
    -- bindings it did not stamp.
    round             INTEGER,
    PRIMARY KEY (collection, link_id, source),
    -- A binding that is not conflicted carries neither (§13).
    CHECK (conflicted = 1 OR (conflict_revision IS NULL AND conflict_object IS NULL)),
    -- ON UPDATE as well as ON DELETE: renaming a collection cascades into
    -- items.collection, this composite key's parent, so without it the rename
    -- is refused one level down (§14).
    FOREIGN KEY (collection, link_id) REFERENCES items(collection, link_id) ON UPDATE CASCADE ON DELETE CASCADE
) STRICT;

-- The summaries (§4.4, Annex A): what a reader lists an item from without
-- its body, one table per kind, at most one row per item, cascading with it.
-- Written by the item's writer under Annex A; none references an object.

-- message/rfc822 (Annex A.1). Every address is also an item_address row.
CREATE TABLE mail_summary (
    collection   TEXT NOT NULL,
    link_id      TEXT NOT NULL,
    message_id   TEXT,                     -- bare Message-ID, angle brackets stripped
    in_reply_to  TEXT NOT NULL DEFAULT '[]' CHECK (json_valid(in_reply_to)),  -- JSON array of bare msg-ids, document order
    subject      TEXT NOT NULL,            -- decoded (RFC 2047), may be empty
    sender       TEXT,                     -- first From addr-spec, canonical (§13)
    sender_name  TEXT,                     -- its display name, decoded, or NULL
    date         TEXT,                     -- RFC 3339 UTC Z at seconds precision, or NULL
    size         INTEGER,                  -- raw message octets, or NULL
    attachment   INTEGER,                  -- 1 has one, 0 has none, NULL not examined
    PRIMARY KEY (collection, link_id),
    FOREIGN KEY (collection, link_id) REFERENCES items(collection, link_id) ON UPDATE CASCADE ON DELETE CASCADE
) STRICT;

-- text/vcard (Annex A.2). Every EMAIL is an item_address row.
CREATE TABLE contact_summary (
    collection TEXT NOT NULL,
    link_id    TEXT NOT NULL,
    uid        TEXT,                       -- the UID verbatim
    fn         TEXT NOT NULL,              -- FN verbatim, unescaped, may be empty
    kind       TEXT,                       -- KIND lowercased: individual, group, org, location; NULL when absent
    org        TEXT,                       -- first ORG component, unescaped, or NULL
    PRIMARY KEY (collection, link_id),
    FOREIGN KEY (collection, link_id) REFERENCES items(collection, link_id) ON UPDATE CASCADE ON DELETE CASCADE
) STRICT;

-- text/calendar, one table per component (Annex A.3 to A.5): a resource is
-- one VEVENT, VTODO or VJOURNAL set. A start is carried verbatim with its
-- parameters; the one resolved instant is items.sort_key.
CREATE TABLE event_summary (
    collection    TEXT NOT NULL,
    link_id       TEXT NOT NULL,
    uid           TEXT,                    -- the UID verbatim
    summary       TEXT NOT NULL,           -- SUMMARY unescaped, may be empty
    location      TEXT,                    -- LOCATION unescaped, or NULL
    dtstart       TEXT,                    -- the value verbatim
    dtstart_tzid  TEXT,                    -- the TZID parameter, or NULL
    dtstart_value TEXT,                    -- 'date-time' or 'date'
    dtend         TEXT,                    -- the value verbatim, or NULL
    recurring     INTEGER,                 -- 1 carries an RRULE or RDATE, 0 none, NULL not examined
    until         TEXT,                    -- the RRULE's UNTIL verbatim, or NULL
    PRIMARY KEY (collection, link_id),
    FOREIGN KEY (collection, link_id) REFERENCES items(collection, link_id) ON UPDATE CASCADE ON DELETE CASCADE
) STRICT;

CREATE TABLE task_summary (
    collection    TEXT NOT NULL,
    link_id       TEXT NOT NULL,
    uid           TEXT,
    summary       TEXT NOT NULL,
    dtstart       TEXT,
    dtstart_tzid  TEXT,
    dtstart_value TEXT,
    due           TEXT,                    -- the DUE value verbatim, or NULL
    due_tzid      TEXT,
    due_value     TEXT,
    status        TEXT,                    -- STATUS uppercased verbatim, or NULL
    completed     TEXT,                    -- COMPLETED verbatim (always UTC per RFC 5545), or NULL
    percent       INTEGER,                 -- PERCENT-COMPLETE, or NULL
    recurring     INTEGER,
    until         TEXT,
    PRIMARY KEY (collection, link_id),
    FOREIGN KEY (collection, link_id) REFERENCES items(collection, link_id) ON UPDATE CASCADE ON DELETE CASCADE
) STRICT;

CREATE TABLE journal_summary (
    collection    TEXT NOT NULL,
    link_id       TEXT NOT NULL,
    uid           TEXT,
    summary       TEXT NOT NULL,
    dtstart       TEXT,
    dtstart_tzid  TEXT,
    dtstart_value TEXT,
    PRIMARY KEY (collection, link_id),
    FOREIGN KEY (collection, link_id) REFERENCES items(collection, link_id) ON UPDATE CASCADE ON DELETE CASCADE
) STRICT;

-- The people an item names, whatever its kind (§4.4, Annex A.6). One generic
-- table, since "everything about this address" is asked across every kind.
CREATE TABLE item_address (
    collection TEXT NOT NULL,
    link_id    TEXT NOT NULL,
    role       TEXT NOT NULL,              -- from, to, cc, bcc, email, organizer, attendee (§13)
    position   INTEGER NOT NULL,           -- 0-based document order within the role
    address    TEXT NOT NULL,              -- canonical addr-spec (§13)
    name       TEXT,                       -- display name, decoded, or NULL
    PRIMARY KEY (collection, link_id, role, position),
    FOREIGN KEY (collection, link_id) REFERENCES items(collection, link_id) ON UPDATE CASCADE ON DELETE CASCADE
) STRICT;

-- The person axis: every placement naming one address, by role.
CREATE INDEX item_address_by_address ON item_address(address, role, collection);

-- The action queue (§15): mutations requested by processes that do not own the
-- store, applied by the owner in append order.
CREATE TABLE queue (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,  -- global append order
    created_at  TEXT    NOT NULL,                   -- RFC 3339, Z (§13)
    producer    TEXT    NOT NULL,                   -- enqueuing process, diagnostic
    collection  TEXT    NOT NULL REFERENCES collections(id) ON UPDATE CASCADE ON DELETE CASCADE,
    action      TEXT    NOT NULL,                   -- 'add' | 'set-flags' | 'remove' | 'move' | 'copy' | 'update' | 'set-performer' | an intent (§15.3, Annex B)
    payload     TEXT    NOT NULL,                   -- versioned JSON, shape per action (§15)
    object_hash TEXT    REFERENCES objects(hash),   -- pins the payload's body against the collector, or NULL
    attempts    INTEGER NOT NULL DEFAULT 0,
    error       TEXT                                -- last failure; non-NULL means parked
) STRICT;

-- What became of an applied action (§15.2, §15.4), keyed by the queue row's id:
-- application deletes the row, so a producer holding the id its enqueue
-- answered reads here that the row was applied and, for an `add`, the seq of
-- the item it created. Written by the owner in the transaction applying the
-- row, kept at least seven days, then pruned (prune_receipts). A cancelled row
-- leaves none. `seq` names no foreign key: a later move or purge retires the
-- item, and the receipt still says what the add created.
CREATE TABLE receipts (
    id         INTEGER PRIMARY KEY,        -- the applied queue row's id
    applied_at TEXT    NOT NULL,           -- RFC 3339, Z (§13)
    collection TEXT    NOT NULL REFERENCES collections(id) ON UPDATE CASCADE ON DELETE CASCADE,
    seq        INTEGER                     -- the item an `add` created, else NULL
) STRICT;

-- A reader overlays a collection's pending actions (§15.4).
CREATE INDEX queue_by_collection ON queue(collection, id);
-- The owner's drain, store-wide in append order, skipping the parked rows
-- (§15.2). Partial, so it holds only what is pending.
CREATE INDEX queue_pending ON queue(id) WHERE error IS NULL;

-- Cross-source identity lookup (dedup, thread stitching) and refcount navigation.
CREATE INDEX items_by_object ON items(object_hash);
CREATE INDEX bindings_by_object ON bindings(base_object);
-- The collector's scan (§5). Partial, so it holds only what is about to be
-- collected and is empty at rest.
CREATE INDEX objects_garbage ON objects(refcount) WHERE refcount <= 0;
-- The other three pointers at an object, so recompute_refcounts reaches every
-- reference by index rather than scanning items, bindings and queue once per
-- object.
CREATE INDEX items_by_conflict_object ON items(conflict_object);
CREATE INDEX bindings_by_conflict_object ON bindings(conflict_object);
CREATE INDEX queue_by_object ON queue(object_hash);
-- The bindings waiting for a decision (list_conflicted_bindings). Partial, so
-- it holds only what is outstanding and is empty at rest: a run reports that
-- count on every invocation, and without it the report scans every binding.
CREATE INDEX bindings_conflicted ON bindings(collection, link_id, source) WHERE conflicted = 1;
-- Resolves a source handle back to its link id (link_for_handle), which is what
-- a batch dropping a placement needs: a drop names a handle, the shared item is
-- keyed by link id. UNIQUE, because a handle names one item per source (§10):
-- a write moving a handle onto another link id retires the old binding first,
-- and one that does not fails here rather than leaving two rows the lookup
-- answers from at random.
CREATE UNIQUE INDEX bindings_by_handle ON bindings(collection, source, handle);
