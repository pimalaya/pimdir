#!/usr/bin/env bash
# Applies the canonical migrations to an empty store and an empty index, then
# prepares every statement under queries/ against them. Needs sqlite3 alone.
set -euo pipefail

root="${1:-$PWD}"
dir="$(mktemp -d)"
db="$dir/pimdir.db"
index="$dir/index.db"

apply() {
    local target="$1" migration version
    for migration in "$2"/*.sql; do
        version="$(basename "$migration" | cut -d_ -f1 | sed 's/^0*//')"
        sqlite3 "$target" "BEGIN; $(cat "$migration") PRAGMA user_version = $version; COMMIT;"
    done
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

# Shadow and virtual tables are not 'table' in pragma_table_list, so the
# STRICT rule reads over an FTS5 index without special-casing it.
strict="SELECT count(*) FROM pragma_table_list
        WHERE schema = 'main' AND type = 'table'
          AND NOT \"strict\" AND name NOT LIKE 'sqlite_%'"

for target in "$db" "$index"; do
    expect "$(basename "$target") version" "$target" "PRAGMA user_version" 1
    expect "$(basename "$target") integrity" "$target" "PRAGMA integrity_check" ok
    expect "$(basename "$target") tables declared without STRICT" "$target" "$strict" 0
done

prepare() {
    local target="$1" file="$2" prelude="$3"

    sqlite3 "$target" "$prelude EXPLAIN $(cat "$file")" > /dev/null || {
        echo "$(basename "$file" .sql) does not prepare against the schema" >&2
        exit 1
    }

    statements=$((statements + 1))
}

statements=0

while read -r file; do
    prepare "$db" "$file" ""
done < <(find "$root/queries/storage" -name '*.sql' | sort)

while read -r file; do
    prepare "$index" "$file" "ATTACH '$db' AS store;"
done < <(find "$root/queries/search" -name '*.sql' | sort)

echo "store and index schemas apply at version 1, $statements statements prepare against them"
