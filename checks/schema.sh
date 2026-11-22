#!/usr/bin/env bash
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Applies the canonical store migrations to an empty store. The canonical text
# calls no JSON function (STORAGE.md §4.1), types the store's columns by CHECK,
# and names every column its triggers and views read and write (§4.4), so a
# migration breaking one of the three fails here. The rehearsal migrations of
# checks/rehearsal/ (§6) then run on the sqlite3 on PATH, as checks/floor.sh
# runs them on the floor. Needs sqlite3 alone; the second argument names the
# rehearsal's directory.
set -euo pipefail

root="${1:-$PWD}"
rehearsal="${2:-$root/checks/rehearsal}"
dir="$(mktemp -d)"
trap 'rm -rf "$dir"' EXIT
db="$dir/pimdir.db"

apply() {
    local target="$1" migration version
    for migration in "$2"/*.sql; do
        version="$(basename "$migration" | cut -d_ -f1 | sed 's/^0*//')"
        sqlite3 "$target" "BEGIN; $(cat "$migration")"$'\n'"PRAGMA user_version = $version; COMMIT;"
    done
}

# A JSON function in any case, JSON(), json_extract (…), jsonb_each(), or the
# -> and ->> operators, which call them; read with the comments dropped, the
# canonical text holding no `--` inside a literal.
json="$(find "$root/migrations" -name '*.sql' | sort | while read -r file; do
    sed 's/--.*//' "$file" | grep -qiE '\bjson[a-z0-9_]*[[:space:]]*\(|->' && echo "$file"
done || true)"
[ -z "$json" ] || {
    echo "the canonical text calls a JSON function:" $json >&2
    exit 1
}

apply "$db" "$root/migrations/storage"

expect() {
    local got
    got="$(sqlite3 "$2" "$3")"
    [ "$got" = "$4" ] || {
        echo "$1: expected $4, got $got" >&2
        exit 1
    }
}

# The store's types are held by CHECK rather than STRICT, so it loads on an
# older SQLite (STORAGE.md §4.1): every column but a rowid alias names its
# declared type in a typeof() check, with 'null' exactly when it may be NULL,
# a key column never.
untyped="SELECT group_concat(m.name || '.' || p.name, ' ') FROM sqlite_schema m, pragma_table_info(m.name) p
         WHERE m.type = 'table' AND m.name NOT LIKE 'sqlite_%'
           AND NOT (p.pk = 1 AND upper(p.type) = 'INTEGER'
                    AND (SELECT count(*) FROM pragma_table_info(m.name) WHERE pk > 0) = 1)
           AND instr(m.sql, CASE WHEN p.\"notnull\" OR p.pk > 0
                                 THEN 'CHECK (typeof(' || p.name || ') = ''' || lower(p.type) || ''')'
                                 ELSE 'CHECK (typeof(' || p.name || ') IN (''' || lower(p.type) || ''', ''null''))' END) = 0"
store_strict="SELECT count(*) FROM pragma_table_list WHERE schema = 'main' AND \"strict\""

expect "pimdir.db version" "$db" "PRAGMA user_version" 1
expect "pimdir.db integrity" "$db" "PRAGMA integrity_check" ok
expect "pimdir.db tables declared STRICT" "$db" "$store_strict" 0
expect "pimdir.db columns without their typeof() check" "$db" "$untyped" ""
expect "pimdir.db auto_vacuum" "$db" "PRAGMA auto_vacuum" 2

# A trigger or a view names the columns it reads and writes (STORAGE.md
# §4.4), so a column a later version adds changes none: no `*` read, no
# INSERT without a column list.
star="$(grep -rliE 'SELECT[[:space:]]+(DISTINCT[[:space:]]+)?\*|RETURNING[[:space:]]+\*|[a-z_]\.\*' \
    "$root/migrations" || true)"
positional="$(grep -rlizE 'INSERT[[:space:]]+(OR[[:space:]]+[a-z]+[[:space:]]+)?INTO[[:space:]]+[a-z_.]+[[:space:]]+(VALUES|SELECT|DEFAULT|WITH)\b' \
    "$root/migrations" || true)"
[ -z "$star$positional" ] || {
    echo "the canonical schema reads * or inserts without a column list:" $star $positional >&2
    exit 1
}

bash "$rehearsal/run.sh" "$root" sqlite3

objects="$(sqlite3 "$db" "SELECT count(*) FROM sqlite_schema WHERE name NOT LIKE 'sqlite_%'")"
echo "the store schema applies at version 1, $objects objects, typed by CHECK, calling no JSON function and naming every column it reads and writes"
