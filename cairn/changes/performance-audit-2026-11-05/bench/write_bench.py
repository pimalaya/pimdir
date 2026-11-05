"""Write-path bench over pimdir's canonical store schema (storage-draft-08).

Writes N new mail placements in batches of 500, each with two flags, one
binding with two base flags, a summary and four addresses, through prepared
statements, under several schema variants. Prints the median ms per message
of three runs and the database size per message.

Usage: python3 -I write_bench.py SCHEMA_SQL DATA_DIR [N]
"""

import os
import random
import sqlite3
import statistics
import sys
import time

SCHEMA = open(sys.argv[1]).read()
DATA = sys.argv[2]
N = int(sys.argv[3]) if len(sys.argv) > 3 else 20000
BATCH = 500

INIT_META = """INSERT INTO store_meta(id, format, format_version, version, read_version,
 produce_version, store_id, incarnation, hash_algo, created_at, derivation)
VALUES(1, 'pimdir', 'storage-draft-08', 1, 1, 1, lower(hex(randomblob(16))), 1,
 'blake3', strftime('%Y-%m-%dT%H:%M:%fZ','now'), 3)"""

STAMP_TRIGGERS = ["items_stamp_insert", "items_stamp_update", "items_stamp_request",
                  "placement_flag_stamp_insert"]


def pending_schema(text):
    """The plan's opt-in pending stamp: -2 skipped by the stamp triggers."""
    text = text.replace(
        "CREATE TRIGGER items_stamp_insert AFTER INSERT ON items\nBEGIN",
        "CREATE TRIGGER items_stamp_insert AFTER INSERT ON items\nWHEN NEW.changed <> -2\nBEGIN")
    text = text.replace(
        "  OR OLD.conflict_object IS NOT NEW.conflict_object\nBEGIN",
        "  OR OLD.conflict_object IS NOT NEW.conflict_object)\n  AND NEW.changed <> -2\nBEGIN")
    text = text.replace(
        "ON items\nWHEN OLD.flags_known IS NOT NEW.flags_known",
        "ON items\nWHEN (OLD.flags_known IS NOT NEW.flags_known")
    text = text.replace(
        "CREATE TRIGGER placement_flag_stamp_insert AFTER INSERT ON placement_flag\nBEGIN\n"
        "    UPDATE items SET changed = -1 WHERE collection = NEW.collection AND link_id = NEW.link_id;",
        "CREATE TRIGGER placement_flag_stamp_insert AFTER INSERT ON placement_flag\nBEGIN\n"
        "    UPDATE items SET changed = -1 WHERE collection = NEW.collection AND link_id = NEW.link_id"
        " AND changed <> -2;")
    assert text.count("<> -2") == 3, "pending rewrite missed a trigger"
    return text


# A sketch of the same tables keyed by an integer placement id: children carry
# `item` instead of (collection, link_id); the indexes and the stamp triggers
# are the canonical ones restated on the id.
SURROGATE = """
PRAGMA auto_vacuum = INCREMENTAL;
CREATE TABLE store_meta (
    id INTEGER PRIMARY KEY CHECK (id = 1), format TEXT NOT NULL DEFAULT 'pimdir',
    format_version TEXT NOT NULL, version INTEGER NOT NULL, read_version INTEGER NOT NULL,
    produce_version INTEGER NOT NULL, store_id TEXT NOT NULL, incarnation INTEGER NOT NULL,
    hash_algo TEXT NOT NULL, created_at TEXT NOT NULL, derivation INTEGER NOT NULL,
    sync_version TEXT, next_seq INTEGER NOT NULL DEFAULT 1, next_change INTEGER NOT NULL DEFAULT 1,
    purges INTEGER NOT NULL DEFAULT 0);
CREATE TABLE collections (id TEXT PRIMARY KEY, account TEXT, kind TEXT NOT NULL, name TEXT NOT NULL,
    changed INTEGER NOT NULL DEFAULT 0);
CREATE TABLE objects (hash TEXT PRIMARY KEY, size INTEGER NOT NULL, refcount INTEGER NOT NULL DEFAULT 0);
CREATE TABLE items (
    id INTEGER PRIMARY KEY,
    collection TEXT NOT NULL CHECK (typeof(collection) = 'text') REFERENCES collections(id) ON UPDATE CASCADE ON DELETE CASCADE,
    link_id TEXT NOT NULL CHECK (typeof(link_id) = 'text'),
    seq INTEGER NOT NULL CHECK (typeof(seq) = 'integer'),
    flags_known INTEGER NOT NULL DEFAULT 0 CHECK (typeof(flags_known) = 'integer') CHECK (flags_known IN (0, 1)),
    object_hash TEXT CHECK (typeof(object_hash) IN ('text', 'null')) REFERENCES objects(hash),
    sort_key TEXT NOT NULL DEFAULT '' CHECK (typeof(sort_key) = 'text'),
    level INTEGER NOT NULL CHECK (typeof(level) = 'integer') CHECK (level IN (1, 2)),
    deleted INTEGER NOT NULL DEFAULT 0 CHECK (typeof(deleted) = 'integer') CHECK (deleted IN (0, 1)),
    retained_at TEXT CHECK (typeof(retained_at) IN ('text', 'null')),
    retained_by TEXT CHECK (typeof(retained_by) IN ('text', 'null')),
    conflicted INTEGER NOT NULL DEFAULT 0 CHECK (typeof(conflicted) = 'integer') CHECK (conflicted IN (0, 1)),
    conflict_object TEXT CHECK (typeof(conflict_object) IN ('text', 'null')) REFERENCES objects(hash),
    changed INTEGER NOT NULL DEFAULT 0 CHECK (typeof(changed) = 'integer'),
    UNIQUE (collection, link_id),
    CHECK (retained_at IS NULL OR deleted = 1),
    CHECK (conflicted = 1 OR conflict_object IS NULL));
CREATE UNIQUE INDEX items_by_seq ON items(collection, seq);
CREATE INDEX items_by_link ON items(link_id);
CREATE INDEX items_retained ON items(collection, seq) WHERE deleted = 1;
CREATE INDEX items_by_sort ON items(collection, sort_key, seq) WHERE deleted = 0;
CREATE INDEX items_by_retained ON items(retained_at, object_hash) WHERE retained_at IS NOT NULL;
CREATE INDEX items_conflicted ON items(collection, seq) WHERE conflicted = 1;
CREATE INDEX items_by_seq_global ON items(seq);
CREATE INDEX items_by_changed ON items(changed);
CREATE INDEX items_by_object ON items(object_hash) WHERE object_hash IS NOT NULL;
CREATE INDEX items_bodiless ON items(collection, deleted, object_hash) WHERE object_hash IS NULL AND deleted = 0;
CREATE TRIGGER items_stamp_insert AFTER INSERT ON items BEGIN
    UPDATE items SET changed = (SELECT next_change FROM store_meta WHERE id = 1) WHERE id = NEW.id;
    UPDATE store_meta SET next_change = next_change + 1 WHERE id = 1; END;
CREATE TRIGGER items_stamp_update AFTER UPDATE OF
    flags_known, object_hash, sort_key, level, deleted, retained_at, conflicted, conflict_object ON items
WHEN OLD.flags_known IS NOT NEW.flags_known OR OLD.object_hash IS NOT NEW.object_hash
  OR OLD.sort_key IS NOT NEW.sort_key OR OLD.level IS NOT NEW.level OR OLD.deleted IS NOT NEW.deleted
  OR OLD.retained_at IS NOT NEW.retained_at OR OLD.conflicted IS NOT NEW.conflicted
  OR OLD.conflict_object IS NOT NEW.conflict_object BEGIN
    UPDATE items SET changed = (SELECT next_change FROM store_meta WHERE id = 1) WHERE id = NEW.id;
    UPDATE store_meta SET next_change = next_change + 1 WHERE id = 1; END;
CREATE TRIGGER items_stamp_request AFTER UPDATE OF changed ON items WHEN NEW.changed = -1 BEGIN
    UPDATE items SET changed = (SELECT next_change FROM store_meta WHERE id = 1) WHERE id = NEW.id;
    UPDATE store_meta SET next_change = next_change + 1 WHERE id = 1; END;
CREATE TABLE placement_flag (
    item INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE,
    flag TEXT NOT NULL CHECK (typeof(flag) = 'text') CHECK (flag != '' AND flag NOT GLOB '*[^!-~]*'),
    PRIMARY KEY (item, flag)) WITHOUT ROWID;
CREATE INDEX placement_flag_by_flag ON placement_flag(flag);
CREATE TRIGGER placement_flag_needs_known BEFORE INSERT ON placement_flag
WHEN (SELECT flags_known FROM items WHERE id = NEW.item) IS NOT 1 BEGIN
    SELECT RAISE(ABORT, 'flags unknown'); END;
CREATE TRIGGER placement_flag_stamp_insert AFTER INSERT ON placement_flag BEGIN
    UPDATE items SET changed = -1 WHERE id = NEW.item; END;
CREATE TABLE bindings (
    item INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE,
    collection TEXT NOT NULL CHECK (typeof(collection) = 'text'),
    source TEXT NOT NULL CHECK (typeof(source) = 'text'),
    handle TEXT NOT NULL CHECK (typeof(handle) = 'text'),
    base_flags_known INTEGER NOT NULL DEFAULT 0 CHECK (base_flags_known IN (0, 1)),
    base_object TEXT REFERENCES objects(hash), base_revision TEXT,
    base_present INTEGER NOT NULL DEFAULT 0 CHECK (base_present IN (0, 1)),
    conflicted INTEGER NOT NULL DEFAULT 0 CHECK (conflicted IN (0, 1)),
    conflict_revision TEXT, conflict_object TEXT REFERENCES objects(hash),
    shared_object TEXT REFERENCES objects(hash), round INTEGER,
    PRIMARY KEY (item, source));
CREATE INDEX bindings_by_object ON bindings(base_object) WHERE base_object IS NOT NULL;
CREATE INDEX bindings_by_conflict_object ON bindings(conflict_object) WHERE conflict_object IS NOT NULL;
CREATE INDEX bindings_by_shared_object ON bindings(shared_object) WHERE shared_object IS NOT NULL;
CREATE INDEX bindings_conflicted ON bindings(item, source) WHERE conflicted = 1;
CREATE UNIQUE INDEX bindings_by_handle ON bindings(collection, source, handle);
CREATE INDEX bindings_by_source ON bindings(source);
CREATE TABLE binding_base_flag (
    item INTEGER NOT NULL, source TEXT NOT NULL,
    flag TEXT NOT NULL CHECK (flag != '' AND flag NOT GLOB '*[^!-~]*'),
    PRIMARY KEY (item, source, flag),
    FOREIGN KEY (item, source) REFERENCES bindings(item, source) ON DELETE CASCADE) WITHOUT ROWID;
CREATE TRIGGER binding_base_flag_needs_known BEFORE INSERT ON binding_base_flag
WHEN (SELECT base_flags_known FROM bindings WHERE item = NEW.item AND source = NEW.source) IS NOT 1 BEGIN
    SELECT RAISE(ABORT, 'base flags unknown'); END;
CREATE TABLE mail_summary (
    item INTEGER PRIMARY KEY REFERENCES items(id) ON DELETE CASCADE,
    message_id TEXT, subject TEXT NOT NULL CHECK (typeof(subject) = 'text'), sender TEXT,
    sender_name TEXT, date TEXT, size INTEGER, attachment INTEGER, invitation TEXT);
CREATE TABLE item_address (
    item INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE,
    role TEXT NOT NULL CHECK (typeof(role) = 'text'),
    position INTEGER NOT NULL CHECK (typeof(position) = 'integer'),
    address TEXT NOT NULL CHECK (typeof(address) = 'text'),
    name TEXT CHECK (typeof(name) IN ('text', 'null')),
    PRIMARY KEY (item, role, position)) WITHOUT ROWID;
CREATE INDEX item_address_by_address ON item_address(address, role);
"""

CANONICAL_STATEMENTS = {
    "seq": "UPDATE store_meta SET next_seq = next_seq + 1 WHERE id = 1 RETURNING next_seq - 1",
    "item": "INSERT INTO items(collection, link_id, seq, flags_known, object_hash, sort_key, level,"
            " deleted, conflicted, conflict_object, changed) VALUES(?, ?, ?, 1, NULL, ?, 1, 0, 0, NULL, ?)",
    "flag": "INSERT INTO placement_flag(collection, link_id, flag) VALUES(?, ?, ?)",
    "binding": "INSERT INTO bindings(collection, link_id, source, handle, base_flags_known, base_object,"
               " base_revision, base_present, conflicted, conflict_revision, conflict_object, shared_object)"
               " VALUES(?, ?, 'imap', ?, 1, NULL, NULL, 1, 0, NULL, NULL, NULL)",
    "base_flag": "INSERT INTO binding_base_flag(collection, link_id, source, flag) VALUES(?, ?, 'imap', ?)",
    "summary": "INSERT INTO mail_summary(collection, link_id, message_id, subject, sender, sender_name,"
               " date, size, attachment, invitation) VALUES(?, ?, ?, ?, ?, ?, ?, ?, 0, NULL)"
               " ON CONFLICT(collection, link_id) DO UPDATE SET subject = excluded.subject",
    "address": "INSERT INTO item_address(collection, link_id, role, position, address, name)"
               " VALUES(?, ?, ?, ?, ?, ?)",
}

SURROGATE_STATEMENTS = {
    "seq": CANONICAL_STATEMENTS["seq"],
    "item": "INSERT INTO items(collection, link_id, seq, flags_known, object_hash, sort_key, level,"
            " deleted, conflicted, conflict_object, changed) VALUES(?, ?, ?, 1, NULL, ?, 1, 0, 0, NULL, ?)"
            " RETURNING id",
    "flag": "INSERT INTO placement_flag(item, flag) VALUES(?, ?)",
    "binding": "INSERT INTO bindings(item, collection, source, handle, base_flags_known, base_object,"
               " base_revision, base_present, conflicted, conflict_revision, conflict_object, shared_object)"
               " VALUES(?, ?, 'imap', ?, 1, NULL, NULL, 1, 0, NULL, NULL, NULL)",
    "base_flag": "INSERT INTO binding_base_flag(item, source, flag) VALUES(?, 'imap', ?)",
    "summary": "INSERT INTO mail_summary(item, message_id, subject, sender, sender_name, date, size,"
               " attachment, invitation) VALUES(?, ?, ?, ?, ?, ?, ?, 0, NULL)"
               " ON CONFLICT(item) DO UPDATE SET subject = excluded.subject",
    "address": "INSERT INTO item_address(item, role, position, address, name) VALUES(?, ?, ?, ?, ?)",
}


def messages(n, seed=7):
    rng = random.Random(seed)
    people = [f"person{p}@example{p % 40}.org" for p in range(2000)]
    for i in range(n):
        day = 1_600_000_000 + rng.randrange(0, 5 * 365 * 86400)
        date = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(day))
        mid = f"{rng.getrandbits(64):016x}.{i}@mail.example.com"
        flags = ["\\Seen" if i % 3 == 0 else "\\Answered",
                 "\\Flagged" if i % 7 == 0 else "NonJunk"]
        addrs = [("from", 0, rng.choice(people)), ("to", 0, rng.choice(people)),
                 ("to", 1, rng.choice(people)), ("cc", 0, rng.choice(people))]
        yield i, mid, date, flags, addrs


def build(variant, path, n, cached=True):
    for suffix in ("", "-wal", "-shm"):
        if os.path.exists(path + suffix):
            os.remove(path + suffix)
    conn = sqlite3.connect(path, isolation_level=None, cached_statements=128 if cached else 0)
    conn.execute("PRAGMA foreign_keys = ON")
    conn.execute("PRAGMA journal_mode = WAL")
    conn.execute("PRAGMA synchronous = FULL")
    conn.execute("PRAGMA secure_delete = ON")
    surrogate = variant.startswith("surrogate")
    schema = SURROGATE if surrogate else SCHEMA
    if variant in ("pending", "surrogate-pending"):
        schema = pending_schema(schema) if not surrogate else schema
    conn.executescript(schema)
    conn.execute("BEGIN")
    if variant == "no-stamp":
        for name in STAMP_TRIGGERS:
            conn.execute(f"DROP TRIGGER {name}")
    if variant == "surrogate-pending":
        conn.execute("DROP TRIGGER items_stamp_insert")
        conn.execute("""CREATE TRIGGER items_stamp_insert AFTER INSERT ON items WHEN NEW.changed <> -2 BEGIN
            UPDATE items SET changed = (SELECT next_change FROM store_meta WHERE id = 1) WHERE id = NEW.id;
            UPDATE store_meta SET next_change = next_change + 1 WHERE id = 1; END""")
        conn.execute("DROP TRIGGER placement_flag_stamp_insert")
        conn.execute("""CREATE TRIGGER placement_flag_stamp_insert AFTER INSERT ON placement_flag BEGIN
            UPDATE items SET changed = -1 WHERE id = NEW.item AND changed <> -2; END""")
    conn.execute(INIT_META)
    conn.execute("INSERT INTO collections(id, account, kind, name) VALUES('acct/INBOX', 'acct',"
                 " 'message/rfc822', 'INBOX')")
    conn.execute("COMMIT")

    pending = variant in ("pending", "surrogate-pending")
    stamp = -2 if pending else 0
    s = SURROGATE_STATEMENTS if surrogate else CANONICAL_STATEMENTS
    col = "acct/INBOX"
    began = time.perf_counter()
    conn.execute("BEGIN")
    for i, mid, date, flags, addrs in messages(n):
        seq = conn.execute(s["seq"]).fetchone()[0]
        if surrogate:
            item = conn.execute(s["item"], (col, mid, seq, date, stamp)).fetchone()[0]
            for flag in flags:
                conn.execute(s["flag"], (item, flag))
            conn.execute(s["binding"], (item, col, str(100000 + i)))
            for flag in flags:
                conn.execute(s["base_flag"], (item, flag))
            conn.execute(s["summary"], (item, mid, f"Subject number {i} about things", addrs[0][2],
                                        "Some Sender", date, 4000 + i % 5000))
            for role, pos, addr in addrs:
                conn.execute(s["address"], (item, role, pos, addr, "Some Name"))
        else:
            conn.execute(s["item"], (col, mid, seq, date, stamp))
            for flag in flags:
                conn.execute(s["flag"], (col, mid, flag))
            conn.execute(s["binding"], (col, mid, str(100000 + i)))
            for flag in flags:
                conn.execute(s["base_flag"], (col, mid, flag))
            conn.execute(s["summary"], (col, mid, mid, f"Subject number {i} about things", addrs[0][2],
                                        "Some Sender", date, 4000 + i % 5000))
            for role, pos, addr in addrs:
                conn.execute(s["address"], (col, mid, role, pos, addr, "Some Name"))
        if (i + 1) % BATCH == 0:
            if pending:
                conn.execute("UPDATE items SET changed = -1 WHERE changed = -2")
            conn.execute("COMMIT")
            conn.execute("BEGIN")
    if pending:
        conn.execute("UPDATE items SET changed = -1 WHERE changed = -2")
    conn.execute("COMMIT")
    elapsed = time.perf_counter() - began

    stamps = conn.execute("SELECT count(DISTINCT changed), min(changed), max(changed),"
                          " (SELECT next_change FROM store_meta) FROM items").fetchone()
    conn.execute("PRAGMA wal_checkpoint(TRUNCATE)")
    conn.close()
    return elapsed, os.path.getsize(path), stamps


if __name__ == "__main__":
    variants = sys.argv[4].split(",") if len(sys.argv) > 4 else [
        "canonical", "no-stamp", "pending", "surrogate", "surrogate-pending"]
    for variant in variants:
        cached = not variant.endswith("-reprepare")
        name = variant.removesuffix("-reprepare")
        runs = []
        for run in range(3):
            path = os.path.join(DATA, f"{variant}.db")
            elapsed, size, stamps = build(name, path, N, cached)
            runs.append(elapsed)
        ms = statistics.median(runs) * 1000 / N
        print(f"{variant:24s} {ms:7.4f} ms/msg  runs={[round(r, 2) for r in runs]}s"
              f"  size/msg={size / N:7.0f} B  stamps(distinct,min,max,next)={stamps}")
