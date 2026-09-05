#!/usr/bin/env bash
# Keeps the documents and queries/ naming the same statements: every statement
# file is named in a document, and every snake_case identifier a document
# writes in backticks is a statement, a table, a column, a pragma or a vector
# field. Needs sqlite3 alone, to read the tables and columns off the schemas.
set -euo pipefail

root="${1:-$PWD}"
dir="$(mktemp -d)"
documents=(OVERVIEW.md STORAGE.md SYNC.md SEARCH.md GUIDE.md README.md vectors/README.md)
failures=0

for part in storage search; do
    for migration in "$root"/migrations/$part/*.sql; do
        sqlite3 "$dir/$part.db" < "$migration"
    done
done

statements="$(find "$root/queries" -name '*.sql' -exec basename {} .sql \; | sort -u)"

known="$(
    for part in storage search; do
        sqlite3 "$dir/$part.db" "SELECT name FROM sqlite_schema WHERE name NOT LIKE 'sqlite_%';
            SELECT p.name FROM sqlite_schema s, pragma_table_info(s.name) p WHERE s.type IN ('table', 'view');"
    done
    # Pragmas, SQLite features, vector fields and JSON keys the documents write.
    printf '%s\n' user_version data_version foreign_keys journal_mode locking_mode integrity_check \
        foreign_key_check table_info table_list contentless_delete json_each json_valid \
        sqlite_schema core_autocrlf base32 body_hex body_len input_hex input_utf8 digest_hex \
        name_chars digest_bytes if_match set_flags no_uid_conflict collect_garbage
)"

# A backticked identifier, the name alone: a call's parameters are dropped and
# a `<kind>` pattern stands for the five summary kinds.
mentioned="$(
    grep -oh '`[a-z][a-z0-9]*\(_[a-z0-9<>]\+\)\+[(`]' "${documents[@]/#/$root/}" | tr -d '`(' | sort -u |
    while read -r name; do
        case "$name" in
            *'<kind>'*) for kind in mail contact event task journal; do echo "${name//<kind>/$kind}"; done ;;
            *) echo "$name" ;;
        esac
    done | sort -u
)"

# Direction one: a statement nobody names is dead or undocumented. Asked of the
# documents directly, since a one-word statement (hit, coverage) is not in the
# snake_case list above.
while read -r statement; do
    if ! grep -qx "$statement" <<< "$mentioned" && ! grep -q "\`$statement[\`(]" "${documents[@]/#/$root/}"; then
        echo "$statement: under queries/ and named in no document" >&2
        failures=$((failures + 1))
    fi
done <<< "$statements"

# Direction two: an identifier that looks like a statement and is not one.
while read -r name; do
    if ! grep -qx "$name" <<< "$statements" && ! grep -qx "$name" <<< "$known"; then
        echo "$name: named in a document, neither a statement nor a schema name" >&2
        failures=$((failures + 1))
    fi
done <<< "$mentioned"

if [ "$failures" -gt 0 ]; then
    echo "$failures name(s) out of step between the documents and queries/" >&2
    exit 1
fi

echo "$(wc -l <<< "$statements") statements named, every backticked identifier resolves"
