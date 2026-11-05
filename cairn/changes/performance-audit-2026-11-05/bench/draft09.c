/* SPDX-License-Identifier: MIT OR Apache-2.0
 *
 * Bench of storage-draft-09's candidate store schemas against draft-08
 * (performance-audit-2026-11-05). Writes N new mail placements, in batches
 * of 500, as a canonical writer lands a listed page of fresh members, then
 * times the reads a mail list runs. Statements are prepared once and reset,
 * so the times are SQLite's; each statement execution counts as a run.
 *
 * Families: rows (draft-08: every flag a row), cols (the system flags as
 * columns, other flags rows), id (cols keyed by an integer placement id).
 * Statements follow queries/storage, written as SQLite 3.18 runs them (no
 * RETURNING, no upsert: a fresh member needs neither).
 *
 * Usage: draft09 SCHEMA rows|cols|id PENDING(0|1) DB N write|read
 */

#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "sqlite3.h"

enum family { ROWS, COLS, ID };

static sqlite3 *db;
static long runs;

static void die(const char *what) {
    fprintf(stderr, "%s: %s\n", what, sqlite3_errmsg(db));
    exit(1);
}

static double now(void) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return t.tv_sec + t.tv_nsec / 1e9;
}

static void exec(const char *sql) {
    char *err = NULL;
    if (sqlite3_exec(db, sql, NULL, NULL, &err) != SQLITE_OK) {
        fprintf(stderr, "%s\n%s\n", err, sql);
        exit(1);
    }
}

static sqlite3_stmt *prep(const char *sql) {
    sqlite3_stmt *st;
    if (sqlite3_prepare_v2(db, sql, -1, &st, NULL) != SQLITE_OK) {
        fprintf(stderr, "%s\n", sql);
        die("prepare");
    }
    return st;
}

static void bt(sqlite3_stmt *st, const char *name, const char *v) {
    int at = sqlite3_bind_parameter_index(st, name);
    if (!at) {
        fprintf(stderr, "no parameter %s in %s\n", name, sqlite3_sql(st));
        exit(1);
    }
    sqlite3_bind_text(st, at, v, -1, SQLITE_TRANSIENT);
}

static void bi(sqlite3_stmt *st, const char *name, sqlite3_int64 v) {
    int at = sqlite3_bind_parameter_index(st, name);
    if (!at) {
        fprintf(stderr, "no parameter %s in %s\n", name, sqlite3_sql(st));
        exit(1);
    }
    sqlite3_bind_int64(st, at, v);
}

/* Runs a statement to its end, answering its first column's last value. */
static sqlite3_int64 run(sqlite3_stmt *st) {
    sqlite3_int64 last = 0;
    int rc;
    runs++;
    while ((rc = sqlite3_step(st)) == SQLITE_ROW) {
        last = sqlite3_column_int64(st, 0);
    }
    if (rc != SQLITE_DONE) {
        fprintf(stderr, "%s\n", sqlite3_sql(st));
        die("step");
    }
    sqlite3_reset(st);
    sqlite3_clear_bindings(st);
    return last;
}

static uint64_t rng = 0x9e3779b97f4a7c15ULL;
static uint64_t next(void) {
    rng ^= rng << 13;
    rng ^= rng >> 7;
    rng ^= rng << 17;
    return rng;
}

/* One fresh message: its key, date, system flags and keywords, addresses. */
struct message {
    char link[64];
    char date[32];
    int marks;          /* \Seen 1, \Answered 2, \Flagged 4 */
    const char *keyword; /* a keyword, or NULL */
    char addr[4][40];
};

static const char *ROLE[4] = {"from", "to", "to", "cc"};
static const int POS[4] = {0, 0, 1, 0};
static const char *SYSTEM[3] = {"\\Seen", "\\Answered", "\\Flagged"};

static void message(long i, struct message *m) {
    time_t t = 1600000000 + (time_t)(next() % (5 * 365 * 86400ULL));
    struct tm tm;
    gmtime_r(&t, &tm);
    strftime(m->date, sizeof m->date, "%Y-%m-%dT%H:%M:%SZ", &tm);
    snprintf(m->link, sizeof m->link, "%016llx.%ld@mail.example.com",
             (unsigned long long)next(), i);
    m->marks = (i % 3 != 0) | ((i % 5 == 0) << 1) | ((i % 7 == 0) << 2);
    m->keyword = i % 10 == 0 ? "$Forwarded" : NULL;
    for (int a = 0; a < 4; a++) {
        unsigned p = next() % 2000;
        snprintf(m->addr[a], sizeof m->addr[a], "person%u@example%u.org", p, p % 40);
    }
}

static const char *COLLECTION = "acct/INBOX";

/* The statements of a family. */
struct writer {
    sqlite3_stmt *seq_any, *seq_read, *seq_bump, *item, *clear, *bind, *flags,
        *binding, *base, *summary, *unaddress, *address, *senders, *pending;
};

static struct writer writer(enum family f) {
    struct writer w;
    w.seq_any = prep(
        "SELECT held.seq FROM items AS held JOIN collections AS there ON there.id = held.collection "
        "JOIN collections AS here ON here.id = :collection "
        "WHERE held.link_id = :link_id AND there.kind = here.kind LIMIT 1");
    w.seq_read = prep("SELECT next_seq FROM store_meta WHERE id = 1");
    w.seq_bump = prep("UPDATE store_meta SET next_seq = next_seq + 1 WHERE id = 1");
    w.clear = prep("DELETE FROM temp.param");
    w.bind = prep("INSERT INTO temp.param(slot, position, value) VALUES('flags', :position, :value)");
    w.pending = prep("UPDATE items SET changed = -1 WHERE changed = -2");
    if (f == ROWS) {
        w.item = prep(
            "INSERT INTO items(collection, link_id, seq, flags_known, object_hash, sort_key, level, "
            "deleted, conflicted, conflict_object, changed) "
            "VALUES(:collection, :link_id, :seq, 1, NULL, :sort_key, 1, 0, 0, NULL, :changed)");
    } else {
        w.item = prep(
            "INSERT INTO items(collection, link_id, seq, flags_known, marks, object_hash, sort_key, "
            "level, deleted, conflicted, conflict_object, changed) "
            "VALUES(:collection, :link_id, :seq, 1, :marks, NULL, :sort_key, 1, 0, 0, NULL, :changed)");
    }
    if (f == ID) {
        w.flags = prep("INSERT OR IGNORE INTO placement_flag(item, flag) "
                       "SELECT :item, value FROM temp.param WHERE slot = 'flags'");
        w.binding = prep(
            "INSERT INTO bindings(item, collection, source, handle, base_flags_known, base_marks, "
            "base_object, base_revision, base_present, conflicted, conflict_revision, conflict_object, "
            "shared_object) VALUES(:item, :collection, 'imap', :handle, 1, :base_marks, NULL, NULL, 1, "
            "0, NULL, NULL, NULL)");
        w.base = prep("INSERT OR IGNORE INTO binding_base_flag(item, source, flag) "
                      "SELECT :item, 'imap', value FROM temp.param WHERE slot = 'flags'");
        w.summary = prep(
            "INSERT INTO mail_summary(item, message_id, subject, sender, sender_name, date, size, "
            "attachment, invitation) VALUES(:item, :message_id, :subject, :sender, 'Some Sender', "
            ":date, :size, 0, NULL)");
        w.unaddress = prep("DELETE FROM item_address WHERE item = :item");
        w.address = prep("INSERT INTO item_address(item, role, position, address, name) "
                         "VALUES(:item, :role, :position, :address, 'Some Name')");
        w.senders = prep(
            "INSERT INTO item_reference(from_kind, from_link_id, to_kind, to_link_id, role, origin, created_at) "
            "SELECT DISTINCT 'message/rfc822', mi.link_id, 'text/vcard', ci.link_id, 'sender', 'auto', "
            "strftime('%Y-%m-%dT%H:%M:%fZ', 'now') "
            "FROM items mi JOIN collections mc ON mc.id = mi.collection AND mc.kind = 'message/rfc822' "
            "JOIN item_address m ON m.item = mi.id AND m.role = 'from' "
            "JOIN item_address c ON c.address = m.address AND c.role = 'email' "
            "JOIN items ci ON ci.id = c.item AND ci.deleted = 0 "
            "JOIN collections cc ON cc.id = ci.collection AND cc.kind = 'text/vcard' "
            "WHERE mi.link_id BETWEEN coalesce(:link_id, '') AND coalesce(:link_id, x'') AND mi.deleted = 0 "
            "AND NOT (mi.link_id GLOB 'alt:*' OR mi.link_id GLOB 'dup:*' OR mi.link_id GLOB 'hash:*') "
            "AND NOT (ci.link_id GLOB 'alt:*' OR ci.link_id GLOB 'dup:*' OR ci.link_id GLOB 'hash:*') "
            "AND NOT EXISTS (SELECT 1 FROM item_reference r WHERE r.from_kind = 'message/rfc822' "
            "AND r.from_link_id = mi.link_id AND r.to_kind = 'text/vcard' AND r.to_link_id = ci.link_id "
            "AND r.role = 'sender')");
    } else {
        w.flags = prep("INSERT OR IGNORE INTO placement_flag(collection, link_id, flag) "
                       "SELECT :collection, :link_id, value FROM temp.param WHERE slot = 'flags'");
        if (f == ROWS) {
            w.binding = prep(
                "INSERT INTO bindings(collection, link_id, source, handle, base_flags_known, base_object, "
                "base_revision, base_present, conflicted, conflict_revision, conflict_object, shared_object) "
                "VALUES(:collection, :link_id, 'imap', :handle, 1, NULL, NULL, 1, 0, NULL, NULL, NULL)");
        } else {
            w.binding = prep(
                "INSERT INTO bindings(collection, link_id, source, handle, base_flags_known, base_marks, "
                "base_object, base_revision, base_present, conflicted, conflict_revision, conflict_object, "
                "shared_object) VALUES(:collection, :link_id, 'imap', :handle, 1, :base_marks, NULL, NULL, "
                "1, 0, NULL, NULL, NULL)");
        }
        w.base = prep("INSERT OR IGNORE INTO binding_base_flag(collection, link_id, source, flag) "
                      "SELECT :collection, :link_id, 'imap', value FROM temp.param WHERE slot = 'flags'");
        w.summary = prep(
            "INSERT INTO mail_summary(collection, link_id, message_id, subject, sender, sender_name, date, "
            "size, attachment, invitation) VALUES(:collection, :link_id, :message_id, :subject, :sender, "
            "'Some Sender', :date, :size, 0, NULL)");
        w.unaddress = prep("DELETE FROM item_address WHERE collection = :collection AND link_id = :link_id");
        w.address = prep("INSERT INTO item_address(collection, link_id, role, position, address, name) "
                         "VALUES(:collection, :link_id, :role, :position, :address, 'Some Name')");
        w.senders = prep(
            "INSERT INTO item_reference(from_kind, from_link_id, to_kind, to_link_id, role, origin, created_at) "
            "SELECT DISTINCT 'message/rfc822', mi.link_id, 'text/vcard', ci.link_id, 'sender', 'auto', "
            "strftime('%Y-%m-%dT%H:%M:%fZ', 'now') "
            "FROM items mi JOIN collections mc ON mc.id = mi.collection AND mc.kind = 'message/rfc822' "
            "JOIN item_address m ON m.collection = mi.collection AND m.link_id = mi.link_id AND m.role = 'from' "
            "JOIN item_address c ON c.address = m.address AND c.role = 'email' "
            "JOIN collections cc ON cc.id = c.collection AND cc.kind = 'text/vcard' "
            "JOIN items ci ON ci.collection = c.collection AND ci.link_id = c.link_id AND ci.deleted = 0 "
            "WHERE mi.link_id BETWEEN coalesce(:link_id, '') AND coalesce(:link_id, x'') AND mi.deleted = 0 "
            "AND NOT (mi.link_id GLOB 'alt:*' OR mi.link_id GLOB 'dup:*' OR mi.link_id GLOB 'hash:*') "
            "AND NOT (ci.link_id GLOB 'alt:*' OR ci.link_id GLOB 'dup:*' OR ci.link_id GLOB 'hash:*') "
            "AND NOT EXISTS (SELECT 1 FROM item_reference r WHERE r.from_kind = 'message/rfc822' "
            "AND r.from_link_id = mi.link_id AND r.to_kind = 'text/vcard' AND r.to_link_id = ci.link_id "
            "AND r.role = 'sender')");
    }
    return w;
}

/* Binds the flags a family keeps as rows into temp.param, answering how
 * many: every flag for rows, the keyword alone for cols and id. */
static int bind_flags(struct writer *w, enum family f, const struct message *m) {
    int n = 0;
    run(w->clear);
    if (f == ROWS) {
        for (int b = 0; b < 3; b++) {
            if (m->marks & (1 << b)) {
                bi(w->bind, ":position", n++);
                bt(w->bind, ":value", SYSTEM[b]);
                run(w->bind);
            }
        }
    }
    if (m->keyword) {
        bi(w->bind, ":position", n++);
        bt(w->bind, ":value", m->keyword);
        run(w->bind);
    }
    return n;
}

static void land(struct writer *w, enum family f, int pending, long i) {
    struct message m;
    message(i, &m);
    char handle[24], subject[64];
    snprintf(handle, sizeof handle, "%ld", 100000 + i);
    snprintf(subject, sizeof subject, "Subject number %ld about things", i);

    bt(w->seq_any, ":collection", COLLECTION);
    bt(w->seq_any, ":link_id", m.link);
    sqlite3_int64 seq = run(w->seq_any);
    if (!seq) {
        seq = run(w->seq_read);
        run(w->seq_bump);
    }

    bt(w->item, ":collection", COLLECTION);
    bt(w->item, ":link_id", m.link);
    bi(w->item, ":seq", seq);
    bt(w->item, ":sort_key", m.date);
    bi(w->item, ":changed", pending ? -2 : 0);
    if (f != ROWS) {
        bi(w->item, ":marks", m.marks);
    }
    run(w->item);
    sqlite3_int64 item = sqlite3_last_insert_rowid(db);

    /* A fresh row holds no flag, so the canonical retain finds nothing to
     * drop: the writer adds, the base sharing the item's bound list. */
    int kept = (f == ROWS || m.keyword) ? bind_flags(w, f, &m) : 0;
    if (kept) {
        if (f == ID) {
            bi(w->flags, ":item", item);
        } else {
            bt(w->flags, ":collection", COLLECTION);
            bt(w->flags, ":link_id", m.link);
        }
        run(w->flags);
    }

    if (f == ID) {
        bi(w->binding, ":item", item);
    } else {
        bt(w->binding, ":link_id", m.link);
    }
    bt(w->binding, ":collection", COLLECTION);
    bt(w->binding, ":handle", handle);
    if (f != ROWS) {
        bi(w->binding, ":base_marks", m.marks);
    }
    run(w->binding);
    if (kept) {
        if (f == ID) {
            bi(w->base, ":item", item);
        } else {
            bt(w->base, ":collection", COLLECTION);
            bt(w->base, ":link_id", m.link);
        }
        run(w->base);
    }

    if (f == ID) {
        bi(w->summary, ":item", item);
    } else {
        bt(w->summary, ":collection", COLLECTION);
        bt(w->summary, ":link_id", m.link);
    }
    bt(w->summary, ":message_id", m.link);
    bt(w->summary, ":subject", subject);
    bt(w->summary, ":sender", m.addr[0]);
    bt(w->summary, ":date", m.date);
    bi(w->summary, ":size", 4000 + i % 5000);
    run(w->summary);

    if (f == ID) {
        bi(w->unaddress, ":item", item);
    } else {
        bt(w->unaddress, ":collection", COLLECTION);
        bt(w->unaddress, ":link_id", m.link);
    }
    run(w->unaddress);
    for (int a = 0; a < 4; a++) {
        if (f == ID) {
            bi(w->address, ":item", item);
        } else {
            bt(w->address, ":collection", COLLECTION);
            bt(w->address, ":link_id", m.link);
        }
        bt(w->address, ":role", ROLE[a]);
        bi(w->address, ":position", POS[a]);
        bt(w->address, ":address", m.addr[a]);
        run(w->address);
    }

    bt(w->senders, ":link_id", m.link);
    run(w->senders);
}

static void open_store(const char *path, const char *schema_path, int fresh) {
    if (fresh) {
        remove(path);
        char side[512];
        snprintf(side, sizeof side, "%s-wal", path);
        remove(side);
        snprintf(side, sizeof side, "%s-shm", path);
        remove(side);
    }
    if (sqlite3_open(path, &db) != SQLITE_OK) die("open");
    exec("PRAGMA foreign_keys = ON");
    if (fresh) {
        FILE *f = fopen(schema_path, "r");
        if (!f) { perror(schema_path); exit(1); }
        static char schema[1 << 20];
        size_t n = fread(schema, 1, sizeof schema - 1, f);
        schema[n] = 0;
        fclose(f);
        exec("BEGIN");
        exec(schema);
        exec("INSERT INTO store_meta(id, format, format_version, version, read_version, "
             "produce_version, store_id, incarnation, hash_algo, created_at, derivation) "
             "VALUES(1, 'pimdir', 'storage-draft-08', 1, 1, 1, lower(hex(randomblob(16))), 1, "
             "'blake3', strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), 3)");
        exec("INSERT INTO collections(id, account, kind, name) "
             "VALUES('acct/INBOX', 'acct', 'message/rfc822', 'INBOX')");
        exec("INSERT INTO collections(id, account, kind, name) "
             "VALUES('acct/Contacts', 'acct', 'text/vcard', 'Contacts')");
        exec("COMMIT");
        exec("PRAGMA journal_mode = WAL");
    }
    exec("PRAGMA synchronous = FULL");
    exec("PRAGMA secure_delete = ON");
    exec("CREATE TEMP TABLE IF NOT EXISTS param (slot TEXT NOT NULL, position INTEGER NOT NULL, "
         "value, PRIMARY KEY (slot, position))");
}

static sqlite3_int64 scalar(const char *sql) {
    sqlite3_stmt *st = prep(sql);
    sqlite3_int64 v = 0;
    if (sqlite3_step(st) == SQLITE_ROW) v = sqlite3_column_int64(st, 0);
    sqlite3_finalize(st);
    return v;
}

static void write_store(enum family f, int pending, long n) {
    struct writer w = writer(f);
    exec("BEGIN");
    for (long i = 0; i < n; i++) {
        land(&w, f, pending, i);
        if ((i + 1) % 500 == 0 || i + 1 == n) {
            if (pending) run(w.pending);
            exec("COMMIT");
            if (i + 1 < n) exec("BEGIN");
        }
    }
}

/* The median of five runs of a read, in ms, and its rows. */
static double timed(const char *sql, long *rows) {
    sqlite3_stmt *st = prep(sql);
    double samples[5];
    for (int r = 0; r < 5; r++) {
        double began = now();
        long count = 0;
        while (sqlite3_step(st) == SQLITE_ROW) count++;
        sqlite3_reset(st);
        samples[r] = (now() - began) * 1000;
        *rows = count;
    }
    sqlite3_finalize(st);
    for (int a = 0; a < 5; a++)
        for (int b = a + 1; b < 5; b++)
            if (samples[b] < samples[a]) { double t = samples[a]; samples[a] = samples[b]; samples[b] = t; }
    return samples[2];
}

/* The mail list's reads, as each family spells them. */
static void reads(enum family f) {
    const char *seen_rows = "EXISTS (SELECT 1 FROM placement_flag p WHERE p.collection = i.collection "
                            "AND p.link_id = i.link_id AND p.flag = '\\Seen')";
    char unread[512], flags[1024], page_unread[2048], page_all[2048], count_unread[512],
        count_since[512];
    const char *summary_join = f == ID ? "LEFT JOIN mail_summary s ON s.item = i.id"
                                       : "LEFT JOIN mail_summary s ON s.collection = i.collection AND s.link_id = i.link_id";
    if (f == ROWS) {
        snprintf(unread, sizeof unread, "NOT %s", seen_rows);
        snprintf(flags, sizeof flags,
                 "coalesce((SELECT group_concat(p.flag, ' ') FROM placement_flag p "
                 "WHERE p.collection = i.collection AND p.link_id = i.link_id), '')");
    } else {
        snprintf(unread, sizeof unread, "i.marks & 1 = 0");
        snprintf(flags, sizeof flags,
                 "trim(CASE WHEN i.marks & 1 THEN '\\Seen ' ELSE '' END || "
                 "CASE WHEN i.marks & 2 THEN '\\Answered ' ELSE '' END || "
                 "CASE WHEN i.marks & 4 THEN '\\Flagged ' ELSE '' END || "
                 "coalesce((SELECT group_concat(p.flag, ' ') FROM placement_flag p WHERE %s), ''))",
                 f == ID ? "p.item = i.id" : "p.collection = i.collection AND p.link_id = i.link_id");
    }
    snprintf(page_unread, sizeof page_unread,
             "SELECT i.seq, i.link_id, %s, i.sort_key, s.subject, s.sender FROM items i %s "
             "WHERE i.collection = 'acct/INBOX' AND i.deleted = 0 AND (i.sort_key, i.seq) < (x'', 0) "
             "AND %s ORDER BY i.sort_key DESC, i.seq DESC LIMIT 50", flags, summary_join, unread);
    snprintf(page_all, sizeof page_all,
             "SELECT i.seq, i.link_id, %s, i.sort_key, s.subject, s.sender FROM items i %s "
             "WHERE i.collection = 'acct/INBOX' AND i.deleted = 0 AND (i.sort_key, i.seq) < (x'', 0) "
             "ORDER BY i.sort_key DESC, i.seq DESC LIMIT 50", flags, summary_join);
    snprintf(count_unread, sizeof count_unread,
             "SELECT count(*) FROM items i WHERE i.collection = 'acct/INBOX' AND i.deleted = 0 AND %s",
             unread);
    snprintf(count_since, sizeof count_since,
             "SELECT count(*) FROM items i WHERE i.collection = 'acct/INBOX' AND i.deleted = 0 AND %s "
             "AND i.sort_key >= '2024-01-01T00:00:00Z'", unread);
    const char *by_day = "SELECT date(nullif(i.sort_key, ''), '0 minutes') AS day, count(*) FROM items i "
                         "WHERE i.collection = 'acct/INBOX' AND i.deleted = 0 AND i.sort_key >= '' "
                         "GROUP BY day ORDER BY day DESC";
    struct { const char *name, *sql; } cases[] = {
        {"page of 50, unread", page_unread},
        {"page of 50, all, flags read", page_all},
        {"count unread", count_unread},
        {"count unread since 2024", count_since},
        {"count by day", by_day},
    };
    for (size_t c = 0; c < sizeof cases / sizeof cases[0]; c++) {
        long rows;
        double ms = timed(cases[c].sql, &rows);
        printf("    %-30s %9.3f ms  %ld rows\n", cases[c].name, ms, rows);
    }
    sqlite3_stmt *st = prep(count_unread);
    sqlite3_step(st);
    printf("    unread %lld\n", (long long)sqlite3_column_int64(st, 0));
    sqlite3_finalize(st);
}

int main(int argc, char **argv) {
    if (argc != 7) {
        fprintf(stderr, "usage: draft09 SCHEMA rows|cols|id PENDING DB N write|read\n");
        return 2;
    }
    enum family f = !strcmp(argv[2], "rows") ? ROWS : !strcmp(argv[2], "cols") ? COLS : ID;
    int pending = atoi(argv[3]);
    long n = atol(argv[5]);
    int write_mode = !strcmp(argv[6], "write");

    open_store(argv[4], argv[1], 1);
    double began = now();
    write_store(f, pending, n);
    double elapsed = now() - began;
    exec("PRAGMA wal_checkpoint(TRUNCATE)");
    sqlite3_int64 bytes = scalar("PRAGMA page_count") * scalar("PRAGMA page_size");
    sqlite3_int64 distinct = scalar("SELECT count(DISTINCT changed) FROM items WHERE changed > 0");
    sqlite3_int64 drawn = scalar("SELECT next_change - 1 FROM store_meta");
    sqlite3_int64 left = scalar("SELECT count(*) FROM items WHERE changed <= 0");

    if (write_mode) {
        printf("%-6s pending=%d sqlite=%s  %.4f ms/msg  %.1f runs/msg  %lld B/msg  "
               "stamps %lld distinct of %lld drawn, %lld unstamped\n",
               argv[2], pending, sqlite3_libversion(), elapsed * 1000 / n, (double)runs / n,
               (long long)(bytes / n), (long long)distinct, (long long)drawn, (long long)left);
    } else {
        printf("%-6s sqlite=%s  %ld messages\n", argv[2], sqlite3_libversion(), n);
        reads(f);
    }
    sqlite3_close(db);
    return 0;
}
