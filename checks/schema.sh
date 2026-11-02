#!/usr/bin/env bash
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Applies the canonical migrations to an empty store and an empty index, then
# prepares every statement under queries/ against them, with the list
# parameters' table (create_param) in place. The canonical text calls no JSON
# function (STORAGE.md §4.1), types the store's columns by CHECK, and names
# every column it reads and writes (§4.4), so a statement or a migration
# breaking one of the three fails here. Needs sqlite3 alone.
set -euo pipefail

root="${1:-$PWD}"
dir="$(mktemp -d)"
trap 'rm -rf "$dir"' EXIT
db="$dir/pimdir.db"
index="$dir/index.db"

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
json="$(find "$root/migrations" "$root/queries" -name '*.sql' | sort | while read -r file; do
    sed 's/--.*//' "$file" | grep -qiE '\bjson[a-z0-9_]*[[:space:]]*\(|->' && echo "$file"
done || true)"
[ -z "$json" ] || {
    echo "the canonical text calls a JSON function:" $json >&2
    exit 1
}

apply "$db" "$root/migrations/storage"
apply "$index" "$root/migrations/search"

expect() {
    local got
    got="$(sqlite3 "$2" "$3")"
    [ "$got" = "$4" ] || {
        echo "$1: expected $4, got $got" >&2
        exit 1
    }
}

# The index's shadow and virtual tables are not 'table' in pragma_table_list,
# so its STRICT rule reads over FTS5 without special-casing it (SEARCH.md §2).
strict="SELECT count(*) FROM pragma_table_list
        WHERE schema = 'main' AND type = 'table'
          AND NOT \"strict\" AND name NOT LIKE 'sqlite_%'"

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

for target in "$db" "$index"; do
    expect "$(basename "$target") version" "$target" "PRAGMA user_version" 1
    expect "$(basename "$target") integrity" "$target" "PRAGMA integrity_check" ok
done
expect "index.db tables declared without STRICT" "$index" "$strict" 0
expect "pimdir.db tables declared STRICT" "$db" "$store_strict" 0
expect "pimdir.db columns without their typeof() check" "$db" "$untyped" ""
expect "pimdir.db auto_vacuum" "$db" "PRAGMA auto_vacuum" 2

# A statement names the columns it reads and writes (STORAGE.md §4.4), so a
# column a later version adds changes none: no `*` read, no INSERT without a
# column list, in a statement or a trigger.
star="$(grep -rliE 'SELECT[[:space:]]+(DISTINCT[[:space:]]+)?\*|RETURNING[[:space:]]+\*|[a-z_]\.\*' \
    "$root/migrations" "$root/queries" || true)"
positional="$(grep -rlizE 'INSERT[[:space:]]+(OR[[:space:]]+[a-z]+[[:space:]]+)?INTO[[:space:]]+[a-z_.]+[[:space:]]+(VALUES|SELECT|DEFAULT|WITH)\b' \
    "$root/migrations" "$root/queries" || true)"
[ -z "$star$positional" ] || {
    echo "a canonical statement reads * or inserts without a column list:" $star $positional >&2
    exit 1
}

prepare() {
    local target="$1" file="$2" prelude="$3"

    sqlite3 "$target" " $prelude EXPLAIN $(cat "$file")" > /dev/null || {
        echo "$(basename "$file" .sql) does not prepare against the schema" >&2
        exit 1
    }

    statements=$((statements + 1))
}

statements=0

while read -r file; do
    prepare "$db" "$file" "$(cat "$root/queries/storage/read/create_param.sql")"
done < <(find "$root/queries/storage" -name '*.sql' | sort)

while read -r file; do
    prepare "$index" "$file" "ATTACH '$db' AS store; $(cat "$root/queries/storage/read/create_param.sql")"
done < <(find "$root/queries/search" -name '*.sql' | sort)

echo "store and index schemas apply at version 1, $statements statements prepare against them"
