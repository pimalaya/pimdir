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
    -- The next change stamp (§4.5), drawn by the triggers below and stamp_item.
    next_change INTEGER NOT NULL DEFAULT 1,
    -- Purges run so far (§11.2): a deleted row leaves no stamp, so this does.
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
    -- 'manual' | 'prefer-incoming' | 'prefer-existing'
    conflict    TEXT NOT NULL DEFAULT 'manual',
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

-- One row per source syncing a collection (a server, a phone); the sync cursor
-- is per source.
CREATE TABLE sources (
    collection TEXT NOT NULL REFERENCES collections(id) ON UPDATE CASCADE ON DELETE CASCADE,
    source     TEXT NOT NULL,              -- source id ('left', 'right', 'phone')
    checkpoint BLOB,                       -- opaque remote cursor (QRESYNC/JMAP state, DAV sync-token)
    PRIMARY KEY (collection, source)
) STRICT;

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
    flags           TEXT,                  -- JSON array of flag strings
    object_hash     TEXT REFERENCES objects(hash),  -- current body, NULL until hydrated
    sort_key        TEXT NOT NULL DEFAULT '',  -- the kind's ordering key, '' when unknown (§9.3)
    level           INTEGER NOT NULL,      -- detail ladder: 0 probed, 1 meta, 2 full
    deleted         INTEGER NOT NULL DEFAULT 0,     -- 1 while a delete propagates across sources
    retained_at     TEXT,                  -- RFC 3339 instant the last binding vanished (§11)
    retained_by     TEXT,                  -- the source whose removal retired it, diagnostic
    conflicted      INTEGER NOT NULL DEFAULT 0,     -- 1 while a content conflict is unresolved
    conflict_object TEXT REFERENCES objects(hash),  -- the diverging body a Manual conflict recorded
    changed         INTEGER NOT NULL DEFAULT 0,     -- the change stamp (§4.5), trigger-maintained
    PRIMARY KEY (collection, link_id)
) STRICT;

-- Resolves a public id back to the internal link id.
CREATE UNIQUE INDEX items_by_seq ON items(collection, seq);
-- "Does this link id already have a seq?", which is what makes every placement
-- share one, and list_link_placements (§9.2).
CREATE INDEX items_by_link ON items(link_id);
-- Every retained read rides this one index, and it leads with `seq` because the
-- trash listing pages on the public id (§14.1): ordering by anything else sorts
-- every retained row in the collection to return one page.
CREATE INDEX items_retained ON items(collection, seq) WHERE retained_at IS NOT NULL;
-- Orders a collection by the kind's own key, `seq` breaking the tie so a keyset
-- page over a non-unique key is total. Without it the only orderings are by
-- link id or by seq, neither of which means anything to a reader (§14.1).
CREATE INDEX items_by_sort ON items(collection, sort_key, seq);
-- The store-global lookup of a public id (§9.1), which items_by_seq cannot
-- serve without scanning: it leads with the collection.
CREATE INDEX items_by_seq_global ON items(seq);
-- The change feed (§4.5): what moved since a stamp is a range seek.
CREATE INDEX items_by_changed ON items(changed);

-- The change stamps (§4.5), drawn here so no writer plumbs them. An update
-- stamps only when an observable column moved, so a restated row stamps
-- nothing; a delete cannot stamp the row it removes and counts a purge.
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
    id, account, kind, name, parent, color, description, sort_order, generation
ON collections
WHEN OLD.id IS NOT NEW.id
  OR OLD.account IS NOT NEW.account
  OR OLD.kind IS NOT NEW.kind
  OR OLD.name IS NOT NEW.name
  OR OLD.parent IS NOT NEW.parent
  OR OLD.color IS NOT NEW.color
  OR OLD.description IS NOT NEW.description
  OR OLD.sort_order IS NOT NEW.sort_order
  OR OLD.generation IS NOT NEW.generation
BEGIN
    UPDATE collections SET changed = (SELECT next_change FROM store_meta WHERE id = 1)
    WHERE id = NEW.id;
    UPDATE store_meta SET next_change = next_change + 1 WHERE id = 1;
END;

-- A handle a source enumerated whose identity is not read yet (SYNC.md §3).
-- A row, not a memory: the checkpoint that stops the source listing it again
-- lands before the fetch that names it, so a crash in between would lose it.
CREATE TABLE probes (
    collection TEXT NOT NULL REFERENCES collections(id) ON UPDATE CASCADE ON DELETE CASCADE,
    source     TEXT NOT NULL,
    handle     TEXT NOT NULL,
    flags      TEXT,                       -- JSON array, NULL when unread (§13)
    PRIMARY KEY (collection, source, handle)
) STRICT;

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
    base_flags        TEXT,                -- JSON array of strings, or NULL
    base_object       TEXT REFERENCES objects(hash),
    base_revision     TEXT,                -- etag/modseq for mutable-content backends
    -- Whether a base exists at all, which its three value columns cannot say: a
    -- source reporting no revision, no body and no flags still agreed, and that
    -- agreement is what tells a pending push from a settled one (§13).
    base_present      INTEGER NOT NULL DEFAULT 0,
    -- This source diverged from its OWN remote (§10), unlike items.conflicted,
    -- which is the cross-source divergence.
    conflicted        INTEGER NOT NULL DEFAULT 0,
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
    PRIMARY KEY (collection, link_id, source),
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
    in_reply_to  TEXT NOT NULL DEFAULT '[]',   -- JSON array of bare msg-ids, document order
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
    action      TEXT    NOT NULL,                   -- 'add' | 'set-flags' | 'remove' | 'move' | 'copy' | 'update' | app-defined (§15.3)
    payload     TEXT    NOT NULL,                   -- versioned JSON, shape per action (§15)
    object_hash TEXT    REFERENCES objects(hash),   -- pins the payload's body against the collector, or NULL
    attempts    INTEGER NOT NULL DEFAULT 0,
    error       TEXT                                -- last failure; non-NULL means parked
) STRICT;

-- The owner drains a collection's pending actions in append order.
CREATE INDEX queue_by_collection ON queue(collection, id);

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
