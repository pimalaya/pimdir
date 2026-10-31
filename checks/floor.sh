#!/usr/bin/env bash
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Loads the canonical store schema on the oldest SQLite it loads on, 3.18
# (STORAGE.md §4.1), and compiles every write path there: for each table an
# insert, an update of every column and a delete, foreign keys on, so every
# trigger and constraint they fire compiles too, runs the CHECK on a body's
# name, whose GLOB class must mean there what it means now, and reads the
# program of an object's delete, whose foreign key checks must seek the partial
# pointer indexes there as they do now. The objects it creates are compared
# with those the sqlite3 on PATH creates from the same text. Needs that sqlite3
# and the floor's shell, named by the second argument.
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

echo "the store schema loads on SQLite $version, $(wc -l < <("$floor" "$dir/floor.db" "$objects")) objects, every write to its $tables tables compiling, a body's name checked, an object's delete seeking its pointers"
