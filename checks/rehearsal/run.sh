#!/usr/bin/env bash
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Rehearses the migrations STORAGE.md §6 foresees and none ships yet, on a
# populated version 1 store, with the sqlite3 shell the second argument names:
# checks/invariants.sh runs it on the sqlite3 on PATH, checks/floor.sh on the
# 3.18.2 floor. Four runs, each from a fresh copy of the populated store:
#
# - additive.sql, as §6 step 3 runs any migration;
# - a rebuild of collections (a fifth kind) and of queue (an AUTOINCREMENT
#   table), the scripts rebuild.sh prints, run as §6 asks of a rebuild:
#   foreign keys off before the transaction, foreign_key_check and
#   integrity_check read before the commit;
# - check.sql, the same fifth kind by an edit of the CHECK under
#   writable_schema, and the same edit refused in defensive mode (§18) where
#   the shell knows the mode;
# - the same rebuild in one transaction with foreign keys on, the form §6
#   forbids, which must not commit with every row.
#
# After each of the first three, every row of every table the store held is
# there, by the columns it had, every schema object is there under its text,
# the three AUTOINCREMENT sequences stand where they stood, a rename still
# cascades, and the store is stamped at version 2.
#
# Usage: run.sh <repository root> <sqlite3>
set -euo pipefail

root="$1"
shell="$2"
here="$(cd "$(dirname "$0")" && pwd)"
dir="$(mktemp -d)"
trap 'rm -rf "$dir"' EXIT
failures=0
sqlite="$("$shell" :memory: 'SELECT sqlite_version();')"

# expect <label> <got> <want>: a difference is shown as the lines that differ,
# a snapshot of a store running to hundreds.
expect() {
    if [ "$2" != "$3" ]; then
        echo "rehearsal on SQLite $sqlite, $1: expected (<) and got (>) differ:" >&2
        diff <(echo "$3") <(echo "$2") | grep '^[<>]' | head -n 20 >&2 || true
        failures=$((failures + 1))
    fi
}

# The dot command leaving defensive mode, where the shell has the mode: a
# current shell opens its database in it, and the floor knows none.
plain=()
if "$shell" :memory: ".dbconfig defensive off" > /dev/null 2>&1; then
    plain=(".dbconfig defensive off")
fi

for migration in "$root"/migrations/storage/*.sql; do
    "$shell" "$dir/base.db" "BEGIN; $(cat "$migration")"$'\n'"PRAGMA user_version = 1; COMMIT;"
done
"$shell" "$dir/base.db" "PRAGMA foreign_keys = ON; $(cat "$here/populate.sql")"

tables="$("$shell" "$dir/base.db" "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name;")"
for table in $tables; do
    [ "$("$shell" "$dir/base.db" "SELECT count(*) FROM $table;")" -gt 0 ] || {
        echo "rehearsal: populate.sql leaves $table empty" >&2
        failures=$((failures + 1))
    }
    "$shell" "$dir/base.db" "SELECT group_concat(name, ', ') FROM pragma_table_info('$table');" > "$dir/columns.$table"
done

# rows <database>: every row of every table the base store holds, by the
# columns the base store gave it, sorted; store_meta without the four columns
# a migration stamps; then the three sequences.
rows() {
    local table columns
    for table in $tables; do
        columns="$(cat "$dir/columns.$table")"
        if [ "$table" = store_meta ]; then
            columns="$(sed 's/format_version, version, read_version, produce_version, //' <<<"$columns")"
        fi
        echo "== $table"
        "$shell" "$1" "SELECT quote($(sed 's/, /), quote(/g' <<<"$columns")) FROM $table;" | sort
    done
    echo "== sqlite_sequence"
    "$shell" "$1" "SELECT name, seq FROM sqlite_sequence ORDER BY name;"
}

# objects <database> [table...]: every schema object but the tables named,
# with its text.
objects() {
    local db="$1" skip; shift
    skip="$(printf "'%s'," "$@")"
    "$shell" "$db" "SELECT type, name, tbl_name, sql FROM sqlite_master
        WHERE name NOT LIKE 'sqlite_%' AND name NOT LIKE 'rehearsal_%'
          AND NOT (type = 'table' AND name IN (${skip}''))
        ORDER BY type, name;"
}

# text <database> <table>: a table's stored text, the quotes a rename puts
# around its name and its runs of blanks dropped.
text() {
    "$shell" "$1" "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = '$2';" | tr -d '"' | tr -s ' \n' ' ' | sed 's/ (/(/'
}

stamp="PRAGMA user_version = 2;
UPDATE store_meta SET version = 2, read_version = :read, produce_version = 1,
       format_version = 'storage-v' || 2 WHERE id = 1;"
judged="PRAGMA foreign_key_check; PRAGMA integrity_check;"

# survives <label> <database> <read_version> [rebuilt table...]: what every
# migration owes (§6).
survives() {
    local label="$1" db="$2" read="$3"; shift 3
    expect "$label: every row of every table survives, the sequences with them" "$(rows "$db")" "$(rows "$dir/base.db")"
    expect "$label: every other schema object survives under its text" "$(objects "$db" "$@")" "$(objects "$dir/base.db" "$@")"
    expect "$label: the store is stamped at version 2, the compatibility versions as stated" \
        "$("$shell" "$db" "SELECT (SELECT user_version FROM pragma_user_version), version, read_version, produce_version, format_version FROM store_meta;")" "2|2|$read|1|storage-v2"
    expect "$label: no foreign key is broken and the file is sound" \
        "$("$shell" "$db" "PRAGMA foreign_keys = ON; $judged" | tr '\n' ' ')" "ok "
    cp "$db" "$dir/probe.db"
    expect "$label: a rename still cascades to the items, the queue and the receipts" \
        "$("$shell" "$dir/probe.db" "PRAGMA foreign_keys = ON; UPDATE collections SET id = 'In' WHERE id = 'INBOX';
            SELECT (SELECT count(*) FROM items WHERE collection = 'In'), (SELECT count(*) FROM queue WHERE collection = 'In'),
                   (SELECT count(*) FROM receipts WHERE collection = 'In'), (SELECT count(*) FROM items WHERE collection = 'INBOX');")" "3|2|1|0"
    expect "$label: the next queue id, the next placement id and the next object id are above every one handed out" \
        "$("$shell" "$dir/probe.db" "PRAGMA foreign_keys = ON;
            INSERT INTO queue(created_at, producer, collection, action, payload) VALUES('2026-11-13T00:00:09.000Z', 'p', 'Cal', 'remove', '{\"v\":1,\"seq\":4}');
            INSERT INTO items(collection, link_id, seq, level) VALUES('Cal', 'next', 99, 1);
            INSERT INTO objects(hash, size) VALUES('dddddddddddddddddddddddddddddddddddddddddddddddddddd', 1);
            SELECT (SELECT max(id) FROM queue), (SELECT id FROM items WHERE link_id = 'next'), (SELECT max(id) FROM objects);")" "4|11|4"
    rm -f "$dir/probe.db"
}

fifth="INSERT INTO collections(id, kind, name) VALUES('Notes', 'text/x-rehearsal', 'Notes'); SELECT count(*) FROM collections WHERE kind = 'text/x-rehearsal';"
sixth="INSERT INTO collections(id, kind, name) VALUES('Other', 'text/x-other', 'Other');"
widened="$(text "$dir/base.db" collections | sed "s|'application/octet-stream'))|'application/octet-stream', 'text/x-rehearsal'))|")"

# --- An additive migration, as step 3 runs it ------------------------------
cp "$dir/base.db" "$dir/additive.db"
"$shell" "$dir/additive.db" "PRAGMA foreign_keys = ON; BEGIN; $(cat "$here/additive.sql")
${stamp//:read/1} COMMIT;"
survives "additive" "$dir/additive.db" 1 collections items queue
expect "additive: what it added is there, the rows reading the new columns' defaults" \
    "$("$shell" "$dir/additive.db" "SELECT (SELECT count(*) FROM sqlite_master WHERE name LIKE 'rehearsal_%'), (SELECT count(*) FROM queue WHERE rehearsal_note IS NULL),
        (SELECT count(*) FROM items WHERE rehearsal_pinned = 0), (SELECT count(*) FROM collections WHERE rehearsal_icon IS NULL);")" "2|2|9|6"

# --- A rebuild, foreign keys off before the transaction ---------------------
script="$(bash "$here/rebuild.sh" "$shell" "$dir/base.db" collections "s|'application/octet-stream'))|'application/octet-stream', 'text/x-rehearsal'))|"
          bash "$here/rebuild.sh" "$shell" "$dir/base.db" queue)"
cp "$dir/base.db" "$dir/rebuild.db"
"$shell" "$dir/rebuild.db" "PRAGMA foreign_keys = OFF; BEGIN; $script
$judged
${stamp//:read/2} COMMIT; PRAGMA foreign_keys = ON;" > "$dir/rebuild.out"
expect "rebuild: foreign_key_check answers no row and integrity_check ok before the commit" "$(tr '\n' ' ' < "$dir/rebuild.out")" "ok "
survives "rebuild" "$dir/rebuild.db" 2 collections queue
expect "rebuild: collections holds its text with the fifth kind and nothing else moved in it" "$(text "$dir/rebuild.db" collections)" "$widened"
expect "rebuild: queue holds the text it held" "$(text "$dir/rebuild.db" queue)" "$(text "$dir/base.db" queue)"
expect "rebuild: the fifth kind is taken, a sixth still refused" \
    "$("$shell" "$dir/rebuild.db" "PRAGMA foreign_keys = ON; $fifth")|$("$shell" "$dir/rebuild.db" "$sixth" 2>&1 | grep -c 'CHECK constraint failed')" "1|1"

# --- The CHECK edited in place, foreign keys on ------------------------------
cp "$dir/base.db" "$dir/check.db"
schema_version="$("$shell" "$dir/check.db" "PRAGMA schema_version;")"
"$shell" "$dir/check.db" "${plain[@]}" "PRAGMA foreign_keys = ON; BEGIN; $(cat "$here/check.sql")
PRAGMA schema_version = $((schema_version + 1));
$judged
${stamp//:read/2} COMMIT;" > "$dir/check.out"
expect "check: integrity_check answers ok before the commit" "$(grep -v defensive "$dir/check.out" | tr '\n' ' ')" "ok "
survives "check" "$dir/check.db" 2 collections
expect "check: the edit landed once, collections holding its text with the fifth kind and nothing else" "$(text "$dir/check.db" collections)" "$widened"
expect "check: the fifth kind is taken, a sixth still refused" \
    "$("$shell" "$dir/check.db" "PRAGMA foreign_keys = ON; $fifth")|$("$shell" "$dir/check.db" "$sixth" 2>&1 | grep -c 'CHECK constraint failed')" "1|1"
if [ "${#plain[@]}" -gt 0 ]; then
    cp "$dir/base.db" "$dir/defensive.db"
    "$shell" "$dir/defensive.db" ".dbconfig defensive on" "PRAGMA foreign_keys = ON; BEGIN; $(cat "$here/check.sql")
    ${stamp//:read/2} COMMIT;" > /dev/null 2>&1 || true
    expect "check: defensive mode refuses the edit, the store left at version 1 with its text" \
        "$("$shell" "$dir/defensive.db" "SELECT version FROM store_meta;")|$(text "$dir/defensive.db" collections)" "1|$(text "$dir/base.db" collections)"
fi

# --- The forbidden form: the rebuild in one transaction, foreign keys on ----
cp "$dir/base.db" "$dir/unsafe.db"
"$shell" "$dir/unsafe.db" "PRAGMA foreign_keys = ON; BEGIN; $script
$judged
${stamp//:read/2} COMMIT;" > "$dir/unsafe.out" 2>&1 || true
committed="$("$shell" "$dir/unsafe.db" "SELECT version FROM store_meta;")"
kept="$("$shell" "$dir/unsafe.db" "SELECT (SELECT count(*) FROM items) || '|' || (SELECT count(*) FROM queue);")"
whole="$("$shell" "$dir/base.db" "SELECT (SELECT count(*) FROM items) || '|' || (SELECT count(*) FROM queue);")"
if [ "$committed" = 2 ] && [ "$kept" = "$whole" ]; then
    echo "rehearsal on SQLite $sqlite: the rebuild in one transaction with foreign keys on committed with every row; §6 forbids it for the rows it loses, so the rehearsal no longer shows why" >&2
    failures=$((failures + 1))
fi
if [ "$committed" = 2 ]; then
    unsafe="commits with $kept of $whole items and queue rows, its checks answering [$(tr '\n' ' ' < "$dir/unsafe.out")]"
else
    unsafe="fails and leaves the store at version 1"
fi

if [ "$failures" -gt 0 ]; then
    echo "$failures rehearsal assertion(s) broken on SQLite $sqlite" >&2
    exit 1
fi
echo "the rehearsal migrations hold on SQLite $sqlite: additive, rebuild and CHECK edit keep every row and object; the forbidden form $unsafe"
