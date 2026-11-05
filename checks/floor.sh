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
# trusted_schema (§18). Needs that sqlite3 and the floor's shell, named by the
# second argument.
set -euo pipefail

root="${1:-$PWD}"
floor="${2:?the sqlite3 shell of the floor SQLite}"
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
    text="$(grep -v '^ *--' "$root/queries/storage/read/$file.sql")"
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
        "$(grep -c 'CORRELATED LIST SUBQUERY' <<<"$steps" || true)$(grep -c 'USING INDEX items_by_sort (collection=? AND .*(sort_key,seq)<(?,?))' <<<"$steps" || true)$(grep -c 'SCAN TABLE items AS i\b' <<<"$steps" || true)" "110"
done
for statement in search_contacts search_calendar search_files; do
    steps="$(floor_plan "$statement" "${pages[@]}")"
    floor_expect "page: $statement merges each collection's seek above the cursor, scanning nothing" \
        "$(grep -c 'CORRELATED LIST SUBQUERY' <<<"$steps" || true)$(grep -c 'USING INDEX items_by_sort (collection=? AND (sort_key,seq)>(?,?))' <<<"$steps" || true)$(grep -c 'SCAN TABLE items AS i\b' <<<"$steps" || true)" "110"
done
for statement in list_mail_page_desc list_items_page_desc; do
    floor_expect "page: $statement seeks its cursor on items_by_sort, the first page's too" \
        "$(floor_plan "$statement" ":after_key=NULL" ":after_seq=NULL" ":limit=10" ":collection='INBOX'" | grep -c 'items_by_sort (collection=? AND (sort_key,seq)<(?,?))' || true)" "1"
done
for statement in list_items_page_asc list_contacts_page_asc list_events_page_asc list_tasks_page_asc list_journals_page_asc list_files_page_asc; do
    floor_expect "page: $statement seeks its cursor on items_by_sort" \
        "$(floor_plan "$statement" ":after_key=''" ":after_seq=0" ":limit=10" ":collection='INBOX'" | grep -c 'items_by_sort (collection=? AND (sort_key,seq)>(?,?))' || true)" "1"
done
for statement in count_mail count_mail_by_day count_unread; do
    floor_expect "since: $statement seeks the floor on items_by_sort" \
        "$(floor_plan "$statement" ":seen=NULL" ":attachment=NULL" ":since='2026-10-06T00:00:00Z'" ":shift=NULL" | grep -c 'items_by_sort (collection=? AND sort_key>?)' || true)" "1"
done
[ "$floor_failures" = 0 ] || exit 1

echo "the store schema loads on SQLite $version, $(wc -l < <("$floor" "$dir/floor.db" "$objects")) objects, every write to its $tables tables compiling, a body's name checked, an object's delete seeking its pointers, its keyset reads seeking their collection and bound, its triggers stored as the canonical text writes them and no trusted_schema there"
