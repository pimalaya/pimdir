-- A storage-draft-09 candidate for bench/draft09.c, not canonical: the system
-- flags as columns (items.marks, bindings.base_marks), every other flag a
-- row, and every child of an item keyed by an integer placement id,
-- items.id. Only the tables a mail write touches and the triggers it fires
-- are here; their columns, CHECKs, indexes and stamp triggers are
-- storage-draft-08's restated on the id. Loads on SQLite 3.18.

PRAGMA auto_vacuum = INCREMENTAL;

CREATE TABLE store_meta (
    id              INTEGER PRIMARY KEY CHECK (id = 1),
    format          TEXT    NOT NULL DEFAULT 'pimdir' CHECK (typeof(format) = 'text'),
    format_version  TEXT    NOT NULL CHECK (typeof(format_version) = 'text'),
    version         INTEGER NOT NULL CHECK (typeof(version) = 'integer'),
    read_version    INTEGER NOT NULL CHECK (typeof(read_version) = 'integer'),
    produce_version INTEGER NOT NULL CHECK (typeof(produce_version) = 'integer'),
    store_id        TEXT    NOT NULL CHECK (typeof(store_id) = 'text')
                    CHECK (length(store_id) = 32 AND store_id NOT GLOB '*[^0-9a-f]*'),
    incarnation     INTEGER NOT NULL CHECK (typeof(incarnation) = 'integer') CHECK (incarnation >= 1),
    hash_algo       TEXT    NOT NULL CHECK (typeof(hash_algo) = 'text') CHECK (hash_algo IN ('blake3')),
    created_at      TEXT    NOT NULL CHECK (typeof(created_at) = 'text'),
    derivation      INTEGER NOT NULL CHECK (typeof(derivation) = 'integer'),
    sync_version    TEXT    CHECK (typeof(sync_version) IN ('text', 'null')),
    next_seq        INTEGER NOT NULL DEFAULT 1 CHECK (typeof(next_seq) = 'integer'),
    next_change     INTEGER NOT NULL DEFAULT 1 CHECK (typeof(next_change) = 'integer'),
    purges          INTEGER NOT NULL DEFAULT 0 CHECK (typeof(purges) = 'integer')
);

CREATE TRIGGER store_meta_identity BEFORE UPDATE OF store_id, incarnation ON store_meta
WHEN NEW.store_id IS NOT OLD.store_id OR NEW.incarnation < OLD.incarnation
BEGIN
    SELECT RAISE(ABORT, 'store identity is fixed');
END;

CREATE TABLE collections (
    id          TEXT PRIMARY KEY CHECK (typeof(id) = 'text'),
    account     TEXT CHECK (typeof(account) IN ('text', 'null')),
    kind        TEXT NOT NULL CHECK (typeof(kind) = 'text') CHECK (kind IN ('', 'message/rfc822', 'text/vcard', 'text/calendar',
                'application/octet-stream')),
    name        TEXT NOT NULL CHECK (typeof(name) = 'text'),
    parent      TEXT CHECK (typeof(parent) IN ('text', 'null')) REFERENCES collections(id) ON UPDATE CASCADE ON DELETE SET NULL,
    color       TEXT CHECK (typeof(color) IN ('text', 'null')),
    description TEXT CHECK (typeof(description) IN ('text', 'null')),
    sort_order  INTEGER CHECK (typeof(sort_order) IN ('integer', 'null')),
    conflict    TEXT NOT NULL DEFAULT 'manual' CHECK (typeof(conflict) = 'text')
                CHECK (conflict IN ('manual', 'prefer-incoming', 'prefer-existing')),
    role        TEXT CHECK (typeof(role) IN ('text', 'null')),
    generation  INTEGER NOT NULL DEFAULT 1 CHECK (typeof(generation) = 'integer'),
    changed     INTEGER NOT NULL DEFAULT 0 CHECK (typeof(changed) = 'integer')
);

CREATE INDEX collections_by_account ON collections(account) WHERE account IS NOT NULL;
CREATE INDEX collections_by_changed ON collections(changed);

CREATE TRIGGER collections_stamp_insert AFTER INSERT ON collections
BEGIN
    UPDATE collections SET changed = (SELECT next_change FROM store_meta WHERE id = 1)
    WHERE id = NEW.id;
    UPDATE store_meta SET next_change = next_change + 1 WHERE id = 1;
END;

CREATE TABLE objects (
    hash     TEXT PRIMARY KEY CHECK (typeof(hash) = 'text')
             CHECK (length(hash) = 52 AND hash NOT GLOB '*[^a-z2-7]*'),
    size     INTEGER NOT NULL CHECK (typeof(size) = 'integer'),
    refcount INTEGER NOT NULL DEFAULT 0 CHECK (typeof(refcount) = 'integer') CHECK (refcount >= 0)
);

-- `id` is the placement id, never reused (AUTOINCREMENT) and never shown: a
-- consumer keeps (collection, seq). `marks` holds \Seen 1, \Answered 2,
-- \Flagged 4, \Draft 8 and \Deleted 16; placement_flag the other flags.
CREATE TABLE items (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    collection      TEXT NOT NULL CHECK (typeof(collection) = 'text') REFERENCES collections(id) ON UPDATE CASCADE ON DELETE CASCADE,
    link_id         TEXT NOT NULL CHECK (typeof(link_id) = 'text'),
    seq             INTEGER NOT NULL CHECK (typeof(seq) = 'integer'),
    flags_known     INTEGER NOT NULL DEFAULT 0 CHECK (typeof(flags_known) = 'integer') CHECK (flags_known IN (0, 1)),
    marks           INTEGER NOT NULL DEFAULT 0 CHECK (typeof(marks) = 'integer'),
    object_hash     TEXT CHECK (typeof(object_hash) IN ('text', 'null')) REFERENCES objects(hash),
    sort_key        TEXT NOT NULL DEFAULT '' CHECK (typeof(sort_key) = 'text'),
    level           INTEGER NOT NULL CHECK (typeof(level) = 'integer') CHECK (level IN (1, 2)),
    deleted         INTEGER NOT NULL DEFAULT 0 CHECK (typeof(deleted) = 'integer') CHECK (deleted IN (0, 1)),
    retained_at     TEXT CHECK (typeof(retained_at) IN ('text', 'null')),
    retained_by     TEXT CHECK (typeof(retained_by) IN ('text', 'null')),
    conflicted      INTEGER NOT NULL DEFAULT 0 CHECK (typeof(conflicted) = 'integer') CHECK (conflicted IN (0, 1)),
    conflict_object TEXT CHECK (typeof(conflict_object) IN ('text', 'null')) REFERENCES objects(hash),
    changed         INTEGER NOT NULL DEFAULT 0 CHECK (typeof(changed) = 'integer'),
    UNIQUE (collection, link_id),
    CHECK (retained_at IS NULL OR deleted = 1),
    CHECK (conflicted = 1 OR conflict_object IS NULL),
    CHECK (flags_known = 1 OR marks = 0)
);

CREATE UNIQUE INDEX items_by_seq ON items(collection, seq);
CREATE INDEX items_by_link ON items(link_id);
CREATE INDEX items_retained ON items(collection, seq) WHERE deleted = 1;
CREATE INDEX items_by_sort ON items(collection, sort_key, seq, marks) WHERE deleted = 0;
CREATE INDEX items_unread ON items(collection, sort_key, seq) WHERE deleted = 0 AND marks & 1 = 0;
CREATE INDEX items_by_retained ON items(retained_at, object_hash) WHERE retained_at IS NOT NULL;
CREATE INDEX items_conflicted ON items(collection, seq) WHERE conflicted = 1;
CREATE INDEX items_by_seq_global ON items(seq);
CREATE INDEX items_by_changed ON items(changed);
CREATE INDEX items_by_object ON items(object_hash) WHERE object_hash IS NOT NULL;
CREATE INDEX items_bodiless ON items(collection, deleted, object_hash) WHERE object_hash IS NULL AND deleted = 0;
CREATE INDEX items_by_conflict_object ON items(conflict_object) WHERE conflict_object IS NOT NULL;

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

CREATE TABLE placement_flag (
    item INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE,
    flag TEXT    NOT NULL CHECK (typeof(flag) = 'text') CHECK (flag != '' AND flag NOT GLOB '*[^!-~]*'),
    PRIMARY KEY (item, flag)
) WITHOUT ROWID;

CREATE INDEX placement_flag_by_flag ON placement_flag(flag);

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

CREATE TRIGGER placement_flag_stamp_insert AFTER INSERT ON placement_flag
BEGIN
    UPDATE items SET changed = -1 WHERE id = NEW.item;
END;

CREATE TRIGGER placement_flag_stamp_delete AFTER DELETE ON placement_flag
BEGIN
    UPDATE items SET changed = -1 WHERE id = OLD.item;
END;

-- `collection` stays for the handle index, which a drop resolves by.
CREATE TABLE bindings (
    item              INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE,
    collection        TEXT NOT NULL CHECK (typeof(collection) = 'text'),
    source            TEXT NOT NULL CHECK (typeof(source) = 'text'),
    handle            TEXT NOT NULL CHECK (typeof(handle) = 'text'),
    base_flags_known  INTEGER NOT NULL DEFAULT 0 CHECK (typeof(base_flags_known) = 'integer') CHECK (base_flags_known IN (0, 1)),
    base_marks        INTEGER NOT NULL DEFAULT 0 CHECK (typeof(base_marks) = 'integer'),
    base_object       TEXT CHECK (typeof(base_object) IN ('text', 'null')) REFERENCES objects(hash),
    base_revision     TEXT CHECK (typeof(base_revision) IN ('text', 'null')),
    base_present      INTEGER NOT NULL DEFAULT 0 CHECK (typeof(base_present) = 'integer') CHECK (base_present IN (0, 1)),
    conflicted        INTEGER NOT NULL DEFAULT 0 CHECK (typeof(conflicted) = 'integer') CHECK (conflicted IN (0, 1)),
    conflict_revision TEXT CHECK (typeof(conflict_revision) IN ('text', 'null')),
    conflict_object   TEXT CHECK (typeof(conflict_object) IN ('text', 'null')) REFERENCES objects(hash),
    shared_object     TEXT CHECK (typeof(shared_object) IN ('text', 'null')) REFERENCES objects(hash),
    round             INTEGER CHECK (typeof(round) IN ('integer', 'null')),
    PRIMARY KEY (item, source),
    CHECK (conflicted = 1 OR (conflict_revision IS NULL AND conflict_object IS NULL)),
    CHECK (base_flags_known = 1 OR base_marks = 0)
);

CREATE INDEX bindings_by_object ON bindings(base_object) WHERE base_object IS NOT NULL;
CREATE INDEX bindings_by_conflict_object ON bindings(conflict_object) WHERE conflict_object IS NOT NULL;
CREATE INDEX bindings_by_shared_object ON bindings(shared_object) WHERE shared_object IS NOT NULL;
CREATE INDEX bindings_conflicted ON bindings(item, source) WHERE conflicted = 1;
CREATE UNIQUE INDEX bindings_by_handle ON bindings(collection, source, handle);

CREATE TABLE binding_base_flag (
    item   INTEGER NOT NULL,
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

CREATE TABLE mail_summary (
    item         INTEGER PRIMARY KEY REFERENCES items(id) ON DELETE CASCADE,
    message_id   TEXT CHECK (typeof(message_id) IN ('text', 'null')),
    subject      TEXT NOT NULL CHECK (typeof(subject) = 'text'),
    sender       TEXT CHECK (typeof(sender) IN ('text', 'null')),
    sender_name  TEXT CHECK (typeof(sender_name) IN ('text', 'null')),
    date         TEXT CHECK (typeof(date) IN ('text', 'null')),
    size         INTEGER CHECK (typeof(size) IN ('integer', 'null')),
    attachment   INTEGER CHECK (typeof(attachment) IN ('integer', 'null')),
    invitation   TEXT CHECK (typeof(invitation) IN ('text', 'null'))
);

CREATE INDEX mail_summary_by_invitation ON mail_summary(invitation) WHERE invitation IS NOT NULL;

CREATE TABLE mail_in_reply_to (
    item     INTEGER NOT NULL REFERENCES mail_summary(item) ON DELETE CASCADE,
    position INTEGER NOT NULL CHECK (typeof(position) = 'integer'),
    msg_id   TEXT    NOT NULL CHECK (typeof(msg_id) = 'text'),
    PRIMARY KEY (item, position)
) WITHOUT ROWID;

CREATE INDEX mail_in_reply_to_by_id ON mail_in_reply_to(msg_id);

CREATE TABLE item_address (
    item     INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE,
    role     TEXT    NOT NULL CHECK (typeof(role) = 'text'),
    position INTEGER NOT NULL CHECK (typeof(position) = 'integer'),
    address  TEXT    NOT NULL CHECK (typeof(address) = 'text'),
    name     TEXT    CHECK (typeof(name) IN ('text', 'null')),
    PRIMARY KEY (item, role, position)
) WITHOUT ROWID;

CREATE INDEX item_address_by_address ON item_address(address, role);

CREATE TABLE item_reference (
    from_kind    TEXT NOT NULL CHECK (typeof(from_kind) = 'text'),
    from_link_id TEXT NOT NULL CHECK (typeof(from_link_id) = 'text'),
    to_kind      TEXT NOT NULL CHECK (typeof(to_kind) = 'text'),
    to_link_id   TEXT NOT NULL CHECK (typeof(to_link_id) = 'text'),
    role         TEXT NOT NULL CHECK (typeof(role) = 'text') CHECK (role IN ('attachment', 'invitation', 'sender', 'parent', 'source', 'related')
                                      OR (substr(role, 1, 2) = 'x-' AND length(role) > 2)),
    origin       TEXT NOT NULL CHECK (typeof(origin) = 'text') CHECK (origin IN ('auto', 'user')),
    created_at   TEXT NOT NULL CHECK (typeof(created_at) = 'text'),
    PRIMARY KEY (from_link_id, from_kind, to_link_id, to_kind, role),
    CHECK (from_kind != to_kind OR from_link_id != to_link_id)
) WITHOUT ROWID;

CREATE INDEX item_reference_to ON item_reference(to_link_id, to_kind, from_link_id, from_kind, role);
