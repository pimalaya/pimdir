#!/usr/bin/env bash
# Applies the canonical migrations to an empty store and an empty index, then
# prepares every named statement in queries/ against them. Needs sqlite3 alone.
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
    local target="$1" file="$2" prelude="$3" name statement
    while read -r name; do
        statement="$(awk -v header="-- name: $name" '
            $0 == header { inside = 1; next }
            /^-- name: /  { inside = 0 }
            inside
        ' "$file")"

        sqlite3 "$target" "$prelude EXPLAIN $statement" > /dev/null || {
            echo "$(basename "$file"): $name does not prepare against the schema" >&2
            exit 1
        }

        statements=$((statements + 1))
    done < <(sed -n 's/^-- name: //p' "$file")
}

statements=0

for file in "$root"/queries/storage/*.sql; do
    prepare "$db" "$file" ""
done

for file in "$root"/queries/search/*.sql; do
    prepare "$index" "$file" "ATTACH '$db' AS store;"
done

echo "store and index schemas apply at version 1, $statements statements prepare against them"
