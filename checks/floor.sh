#!/usr/bin/env bash
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Loads the canonical store schema on the oldest SQLite it loads on, 3.18
# (STORAGE.md §4.1), and compiles every write path there: for each table an
# insert, an update of every column and a delete, foreign keys on, so every
# trigger and constraint they fire compiles too, runs the CHECK on a body's
# name, whose GLOB class must mean there what it means now, and reads the
# program of an object's delete, whose foreign key checks must seek the partial
# pointer indexes there as they do now. The objects it creates, and the text
# of its triggers and views, are compared with those the sqlite3 on PATH
# creates from the same text, and the floor is checked to know no
# trusted_schema (§18). The rehearsal migrations of checks/rehearsal/ (§6) run
# there too: on the floor a table changes only by a rebuild, and a rebuild run
# with foreign keys on commits with every referencing row gone. Needs that
# sqlite3 and the floor's shell, named by the second argument; the third
# names the rehearsal's directory.
set -euo pipefail

root="${1:-$PWD}"
floor="${2:?the sqlite3 shell of the floor SQLite}"
rehearsal="${3:-$root/checks/rehearsal}"
dir="$(mktemp -d)"
trap 'rm -rf "$dir"' EXIT

version="$("$floor" :memory: 'SELECT sqlite_version();')"

apply() {
    local shell="$1" db="$2" migration number
    for migration in "$root"/migrations/storage/*.sql; do
        number="$(basename "$migration" | cut -d_ -f1 | sed 's/^0*//')"
        "$shell" "$db" "BEGIN; $(cat "$migration")"$'\n'"PRAGMA user_version = $number; COMMIT;" || {
            echo "$(basename "$migration") does not load on SQLite $version" >&2
            exit 1
        }
    done
}

objects="SELECT type, name FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' ORDER BY type, name;"

apply "$floor" "$dir/floor.db"
apply sqlite3 "$dir/reference.db"

diff <("$floor" "$dir/floor.db" "$objects") <(sqlite3 "$dir/reference.db" "$objects") >&2 || {
    echo "SQLite $version creates other tables, indexes or triggers than $(sqlite3 :memory: 'SELECT sqlite_version();')" >&2
    exit 1
}

# A store from elsewhere (STORAGE.md §18): the floor knows no trusted_schema,
# so a program there compares the triggers and views a store holds with those
# the canonical text creates, which must read alike whichever SQLite created
# the store.
[ -z "$("$floor" :memory: 'PRAGMA trusted_schema;')" ] || {
    echo "SQLite $version knows trusted_schema, which STORAGE.md §18 says the floor lacks" >&2
    exit 1
}
schema="SELECT type, name, sql FROM sqlite_master WHERE type IN ('trigger', 'view') ORDER BY type, name;"
diff <("$floor" "$dir/floor.db" "$schema") <(sqlite3 "$dir/reference.db" "$schema") >&2 || {
    echo "SQLite $version stores another text for a trigger or a view than $(sqlite3 :memory: 'SELECT sqlite_version();')" >&2
    exit 1
}

tables=0
for table in $("$floor" "$dir/floor.db" "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name;"); do
    columns="$("$floor" "$dir/floor.db" "SELECT group_concat(name || ' = ' || name, ', ') FROM pragma_table_info('$table');")"
    "$floor" "$dir/floor.db" "PRAGMA foreign_keys = ON;
        EXPLAIN INSERT INTO $table DEFAULT VALUES;
        EXPLAIN UPDATE $table SET $columns;
        EXPLAIN DELETE FROM $table;" > /dev/null || {
        echo "$table: a write does not compile on SQLite $version" >&2
        exit 1
    }
    tables=$((tables + 1))
done

# A body's name is checked on the floor as on a current SQLite (STORAGE.md
# §5): 52 characters of lowercase base32 are taken, and a path, an uppercase
# name and a short one are refused, so a store either writes refuses the same
# names.
well_formed="$(printf 'a%.0s' $(seq 52))"
"$floor" "$dir/floor.db" "INSERT INTO objects(hash, size) VALUES('$well_formed', 0);" || {
    echo "objects.hash refuses a well-formed name on SQLite $version" >&2
    exit 1
}
for malformed in ../x "${well_formed^^}" "${well_formed:0:26}"; do
    if "$floor" "$dir/floor.db" "INSERT INTO objects(hash, size) VALUES('$malformed', 0);" 2>/dev/null; then
        echo "objects.hash takes the name [$malformed] on SQLite $version" >&2
        exit 1
    fi
done

# The shapes §13 fixes are refused on the floor as on a current SQLite
# (STORAGE.md §13): one row of each table they bind, well formed, then the
# writes checks/invariants.sh shows refused by the CHECK naming each column,
# each of which must fail here on a constraint and leave the store as it was.
# The floor names the table alone in its message, so the CHECK is told by the
# scenario there and its effect here.
for migration in "$root"/migrations/storage/*.sql; do
    "$floor" "$dir/shapes.db" "BEGIN; $(cat "$migration")"$'\n'"COMMIT;"
done
"$floor" "$dir/shapes.db" "PRAGMA foreign_keys = ON;
    INSERT INTO store_meta(id, format_version, version, read_version, produce_version, store_id, incarnation, hash_algo, created_at, derivation)
        VALUES(1, 'floor', 1, 1, 1, '00000000000000000000000000000000', 1, 'blake3', strftime('%Y-%m-%dT%H:%M:%fZ','now'), 1);
    INSERT INTO collections(id, kind, name) VALUES('INBOX', 'message/rfc822', 'INBOX');
    INSERT INTO objects(hash, size) VALUES('$well_formed', 1);
    INSERT INTO items(id, collection, link_id, seq, level) VALUES(1, 'INBOX', 'a', 1, 2);
    INSERT INTO items(id, collection, link_id, seq, level, deleted, retained_at, retained_by)
        VALUES(2, 'INBOX', 'r', 2, 2, 1, strftime('%Y-%m-%dT%H:%M:%fZ','now'), 'imap');
    INSERT INTO bindings(item, collection, source, handle, base_present, base_object, base_revision)
        VALUES(1, 'INBOX', 'imap', '10', 1, '$well_formed', 'r1');
    INSERT INTO mail_summary(item, subject, date, size, attachment) VALUES(1, 's', '2026-10-06T08:00:00Z', 1, 0);
    INSERT INTO event_summary(item, summary, recurring) VALUES(1, '', 0);
    INSERT INTO task_summary(item, summary, recurring) VALUES(1, '', 0);
    INSERT INTO file_summary(item, name, size) VALUES(1, '', 0);
    INSERT INTO sources(collection, source, covered_since, covered_until, covered_at, round_since, round_until, round_started_at)
        VALUES('INBOX', 'imap', '2026-09-01T00:00:00Z', '2026-10-01T00:00:00Z', strftime('%Y-%m-%dT%H:%M:%fZ','now'),
               '2026-09-01T00:00:00Z', '2026-10-01T00:00:00Z', strftime('%Y-%m-%dT%H:%M:%fZ','now'));
    INSERT INTO queue(created_at, producer, collection, action, payload) VALUES(strftime('%Y-%m-%dT%H:%M:%fZ','now'), 'p', 'INBOX', 'remove', '{}');
    INSERT INTO receipts(id, applied_at, collection, seq) VALUES(9, strftime('%Y-%m-%dT%H:%M:%fZ','now'), 'INBOX', 1);
    INSERT INTO capabilities(source, capability, support) VALUES('imap', 'mail.send', 'full');
    INSERT INTO performers(capability, source) VALUES('mail.send', 'imap');
    INSERT INTO item_reference(from_kind, from_link_id, to_kind, to_link_id, role, origin, created_at)
        VALUES('message/rfc822', 'a', 'message/rfc822', 'r', 'related', 'user', strftime('%Y-%m-%dT%H:%M:%fZ','now'));" || {
    echo "a well-formed row is refused on SQLite $version" >&2
    exit 1
}
shapes="$("$floor" "$dir/shapes.db" .dump)"
refusals=0
while read -r write; do
    [ -n "$write" ] || continue
    refusals=$((refusals + 1))
    for shell in "$floor" sqlite3; do
        answer="$("$shell" "$dir/shapes.db" "PRAGMA foreign_keys = ON; $write;" 2>&1 || true)"
        if [[ "$answer" != *"CHECK constraint failed"* ]]; then
            echo "[$write] is not refused by a constraint on SQLite $("$shell" :memory: 'SELECT sqlite_version();')" >&2
            exit 1
        fi
    done
done <<'SHAPES'
UPDATE items SET retained_at = 'yesterday' WHERE link_id = 'r'
UPDATE items SET retained_at = '2026-10-01T00:00:00Z' WHERE link_id = 'r'
UPDATE items SET retained_at = '2026-10-01T00:00:00.000+00:00' WHERE link_id = 'r'
UPDATE items SET retained_at = '2026-10-01 00:00:00.000Z' WHERE link_id = 'r'
UPDATE store_meta SET created_at = '2026-10-01T00:00:00Z'
UPDATE queue SET created_at = '1790000000'
UPDATE item_reference SET created_at = '2026-10-01'
UPDATE receipts SET applied_at = '2026-10-01T00:00:00Z'
UPDATE sources SET covered_at = '2026-10-01T00:00:00Z'
UPDATE sources SET round_started_at = '2026-10-01T00:00:00Z'
UPDATE sources SET covered_since = '2026-09-01'
UPDATE sources SET covered_until = '2026-10-01T00:00:00.000Z'
UPDATE sources SET round_since = '2026-09-01T00:00:00'
UPDATE sources SET round_until = ''
UPDATE items SET seq = 0 WHERE link_id = 'a'
INSERT INTO items(collection, link_id, seq, level) VALUES('INBOX', 'n', -3, 2)
UPDATE receipts SET seq = 0
INSERT INTO items(collection, link_id, seq, level) VALUES('INBOX', '', 3, 2)
INSERT INTO collections(id, kind, name) VALUES('', 'message/rfc822', '')
UPDATE collections SET account = ''
UPDATE capabilities SET account = ''
UPDATE performers SET account = ''
UPDATE sources SET source = ''
UPDATE bindings SET source = ''
UPDATE capabilities SET source = ''
UPDATE performers SET source = ''
UPDATE bindings SET handle = ''
UPDATE objects SET size = -5
UPDATE mail_summary SET date = '12 Nov 2026'
UPDATE mail_summary SET date = '2026-10-06T08:00:00.000Z'
UPDATE mail_summary SET date = '2026-10-06T08:00:00+00:00'
UPDATE mail_summary SET size = -1
UPDATE file_summary SET size = -1
UPDATE queue SET attempts = -1
UPDATE mail_summary SET attachment = 7
UPDATE event_summary SET recurring = 2
UPDATE task_summary SET recurring = -1
UPDATE items SET retained_by = 'imap' WHERE link_id = 'a'
UPDATE items SET retained_at = NULL WHERE link_id = 'r'
UPDATE bindings SET base_present = 0
UPDATE bindings SET base_present = 0, base_object = NULL
UPDATE bindings SET base_present = 0, base_object = NULL, base_revision = NULL, base_flags_known = 1
SHAPES
if [ "$("$floor" "$dir/shapes.db" .dump)" != "$shapes" ]; then
    echo "a refused write moved a row on SQLite $version" >&2
    exit 1
fi
# What each column may also hold is taken there: a NULL where one is allowed,
# a size of none, a base let go whole.
"$floor" "$dir/shapes.db" "PRAGMA foreign_keys = ON;
    UPDATE mail_summary SET date = NULL, size = NULL, attachment = NULL; UPDATE event_summary SET recurring = NULL;
    UPDATE task_summary SET recurring = 1; UPDATE sources SET covered_since = NULL, round_until = NULL;
    UPDATE receipts SET seq = NULL; UPDATE items SET retained_by = NULL WHERE link_id = 'r'; UPDATE objects SET size = 0;
    UPDATE bindings SET base_present = 0, base_object = NULL, base_revision = NULL;" || {
    echo "a shape §13 allows is refused on SQLite $version" >&2
    exit 1
}

# Every pointer index holds the pointers set alone (STORAGE.md §4.3),
# items_by_object included, so an object's delete checks each pointer at it
# through its index only where an equality is read as implying the pointer is
# set: the program must read the six pointer indexes, never items, bindings or
# the queue whole.
opens() {
    "$1" -separator ' ' "$2" "PRAGMA foreign_keys = ON; EXPLAIN DELETE FROM objects WHERE hash = '$well_formed';" |
        awk '$2 == "OpenRead" {print $4}' | sort -u |
        while read -r root; do "$1" "$2" "SELECT name FROM sqlite_master WHERE rootpage = $root;"; done | sort | tr '\n' ' '
}
pointers="bindings_by_conflict_object bindings_by_object bindings_by_shared_object items_by_conflict_object items_by_object queue_by_object "
for shell in "$floor" sqlite3; do
    [ "$(opens "$shell" "$dir/floor.db")" = "$pointers" ] || {
        echo "an object's delete reads [$(opens "$shell" "$dir/floor.db")] on SQLite $("$shell" :memory: 'SELECT sqlite_version();'), not the pointer indexes alone" >&2
        exit 1
    }
done

# The keyset reads seek on the floor as invariants.sh asserts they do on a
# current SQLite (STORAGE.md §9.3, §14.1), which is where the Android app runs
# them verbatim. The floor has no STRICT, so the list parameters' table there
# leaves `value` untyped: declared `ANY` outside a STRICT table it would take
# NUMERIC affinity, and `x.collection = p.id` would no longer seek its
# collection, a page then sorting the whole collection. The floor's shell has
# no .parameter either, so each parameter is spelled as a literal.
param="CREATE TEMP TABLE param (slot TEXT NOT NULL, position INTEGER NOT NULL, value, PRIMARY KEY (slot, position));
INSERT INTO temp.param VALUES ('collections', 0, 'INBOX'), ('collections', 1, 'Sent');"
floor_plan() {
    local file="$1"; shift
    local text
    case "$file" in */*) ;; *) file="read/$file" ;; esac
    text="$(grep -v '^ *--' "$root/queries/storage/$file.sql")"
    for binding in "$@"; do
        text="${text//${binding%%=*}/${binding#*=}}"
    done
    "$floor" "$dir/floor.db" "$param EXPLAIN QUERY PLAN $text"
}
floor_failures=0
floor_expect() {
    if [ "$2" != "$3" ]; then
        echo "$1: expected [$3], got [$2] on SQLite $version" >&2
        floor_failures=$((floor_failures + 1))
    fi
}
pages=(":after_collection=NULL" ":after_key=NULL" ":after_seq=NULL" ":limit=10" ":pattern='%a%'"
       ":seen=NULL" ":attachment=NULL" ":since=NULL")
for statement in list_mail_page_filtered search_mail; do
    steps="$(floor_plan "$statement" "${pages[@]}")"
    floor_expect "page: $statement merges each collection's seek below the cursor, scanning nothing" \
        "$(grep -c 'CORRELATED LIST SUBQUERY' <<<"$steps" || true)$(grep -cE 'USING (COVERING )?INDEX items_by_sort \(collection=\? AND .*\(sort_key,seq\)<\(\?,\?\)\)' <<<"$steps" || true)$(grep -c 'SCAN TABLE items AS i\b' <<<"$steps" || true)" "110"
done
for statement in search_contacts search_calendar search_files; do
    steps="$(floor_plan "$statement" "${pages[@]}")"
    floor_expect "page: $statement merges each collection's seek above the cursor, scanning nothing" \
        "$(grep -c 'CORRELATED LIST SUBQUERY' <<<"$steps" || true)$(grep -cE 'USING (COVERING )?INDEX items_by_sort \(collection=\? AND \(sort_key,seq\)>\(\?,\?\)\)' <<<"$steps" || true)$(grep -c 'SCAN TABLE items AS i\b' <<<"$steps" || true)" "110"
done
for statement in list_mail_page_desc list_items_page_desc; do
    floor_expect "page: $statement seeks its cursor on items_by_sort, the first page's too" \
        "$(floor_plan "$statement" ":after_key=NULL" ":after_seq=NULL" ":limit=10" ":collection='INBOX'" | grep -c 'items_by_sort (collection=? AND (sort_key,seq)<(?,?))' || true)" "1"
done
for statement in list_items_page_asc list_contacts_page_asc list_events_page_asc list_tasks_page_asc list_journals_page_asc list_files_page_asc; do
    floor_expect "page: $statement seeks its cursor on items_by_sort" \
        "$(floor_plan "$statement" ":after_key=''" ":after_seq=0" ":limit=10" ":collection='INBOX'" | grep -c 'items_by_sort (collection=? AND (sort_key,seq)>(?,?))' || true)" "1"
    floor_expect "page: $statement seeks a NULL cursor, the first page, on items_by_sort" \
        "$(floor_plan "$statement" ":after_key=NULL" ":after_seq=NULL" ":limit=10" ":collection='INBOX'" | grep -c 'items_by_sort (collection=? AND (sort_key,seq)>(?,?))' || true)" "1"
done
floor_expect "page: list_items_page and list_retained_page seek a NULL cursor on their key" \
    "$(floor_plan list_items_page ":after=NULL" ":limit=10" ":collection='INBOX'" | grep -c 'sqlite_autoindex_items_1 (collection=? AND link_id>?)' || true)$(floor_plan list_retained_page ":after=NULL" ":limit=10" ":collection='INBOX'" | grep -c 'items_deleted (collection=? AND seq>?)' || true)" "11"
for statement in count_mail count_mail_by_day; do
    floor_expect "since: $statement seeks the floor on items_by_sort" \
        "$(floor_plan "$statement" ":seen=NULL" ":attachment=NULL" ":since='2026-10-06T00:00:00Z'" ":shift=NULL" | grep -c 'items_by_sort (collection=? AND sort_key>?)' || true)" "1"
done
# The sources of a collection and of the store are read by a loose scan there
# too (§14.1): the recursive text compiles on the floor and seeks the next
# source above the last.
for statement in owner/collection_sources list_sources; do
    floor_expect "sources: ${statement#*/} seeks the next source on bindings_by_handle" \
        "$(floor_plan "$statement" ":collection='INBOX'" | grep -c 'SEARCH TABLE bindings AS b USING COVERING INDEX bindings_by_handle (collection=? AND source>?)' || true)" "1"
done
# The unread count reads items_unread there too (§14.1): the floor ignores a
# hint it cannot use rather than failing on it, so only its plan says the
# partial index, whose WHERE the statement spells term for term, is the one
# read.
for since in NULL "'2026-10-06T00:00:00Z'"; do
    floor_expect "count: count_unread seeks items_unread, never items_by_sort, with :since $since" \
        "$(floor_plan count_unread ":attachment=NULL" ":since=$since" | grep -c 'SEARCH TABLE items AS i USING INDEX items_unread (collection=? AND sort_key>?)' || true)$(floor_plan count_unread ":attachment=NULL" ":since=$since" | grep -c 'items_by_sort' || true)" "10"
done
[ "$floor_failures" = 0 ] || exit 1

# A migration keeps every row on the floor too (§6): the additive one, the
# rebuild with foreign keys off before the transaction and the edit of a
# CHECK, with the rebuild §6 forbids, which loses the rows there silently.
bash "$rehearsal/run.sh" "$root" "$floor"

echo "the store schema loads on SQLite $version, $(wc -l < <("$floor" "$dir/floor.db" "$objects")) objects, every write to its $tables tables compiling, a body's name checked, $refusals mis-shaped writes refused, an object's delete seeking its pointers, its keyset reads seeking their collection and bound, its triggers stored as the canonical text writes them and no trusted_schema there"
