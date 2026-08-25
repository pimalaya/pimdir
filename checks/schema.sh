#!/usr/bin/env bash
# Applies the canonical migrations to an empty database, then prepares every
# named statement in queries/ against the result. Needs sqlite3 alone.
set -euo pipefail

root="${1:-$PWD}"
db="$(mktemp -d)/pimdir.db"

for migration in "$root"/migrations/*.sql; do
    version="$(basename "$migration" | cut -d_ -f1 | sed 's/^0*//')"
    sqlite3 "$db" "BEGIN; $(cat "$migration") PRAGMA user_version = $version; COMMIT;"
done

expect() {
    local got
    got="$(sqlite3 "$db" "$2")"
    [ "$got" = "$3" ] || {
        echo "$1: expected $3, got $got" >&2
        exit 1
    }
}

expect "schema version" "PRAGMA user_version" 1
expect "integrity" "PRAGMA integrity_check" ok
expect "tables declared without STRICT" \
    "SELECT count(*) FROM pragma_table_list
     WHERE schema = 'main' AND type = 'table'
       AND NOT \"strict\" AND name NOT LIKE 'sqlite_%'" 0

statements=0

for file in "$root"/queries/*.sql; do
    while read -r name; do
        statement="$(awk -v header="-- name: $name" '
            $0 == header { inside = 1; next }
            /^-- name: /  { inside = 0 }
            inside
        ' "$file")"

        sqlite3 "$db" "EXPLAIN $statement" > /dev/null || {
            echo "$(basename "$file"): $name does not prepare against the schema" >&2
            exit 1
        }

        statements=$((statements + 1))
    done < <(sed -n 's/^-- name: //p' "$file")
done

echo "schema applies at version 1, $statements statements prepare against it"
