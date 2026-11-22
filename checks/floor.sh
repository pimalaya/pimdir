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
# (STORAGE.md §13): one row of each table they bind, well formed, then writes
# a CHECK naming each column refuses, each of which must fail here, on the
# floor and on the sqlite3 on PATH, on a constraint and leave the store as it
# was.
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
        VALUES(1, 'INBOX', 'imap', '10', 1, 1, 'r1');
    INSERT INTO items(id, collection, link_id, seq, level) VALUES(3, 'INBOX', 'e', 3, 2);
    INSERT INTO items(id, collection, link_id, seq, level) VALUES(4, 'INBOX', 't', 4, 2);
    INSERT INTO items(id, collection, link_id, seq, level) VALUES(5, 'INBOX', 'f', 5, 2);
    INSERT INTO summary(item, component, title, date, size, attachment) VALUES(1, 'mail', 's', '2026-10-06T08:00:00Z', 1, 0);
    INSERT INTO summary(item, component, title, recurring) VALUES(3, 'event', '', 0);
    INSERT INTO summary(item, component, title, recurring) VALUES(4, 'task', '', 0);
    INSERT INTO summary(item, component, title, size) VALUES(5, 'file', '', 0);
    INSERT INTO summary_value(item, role, position, value, name) VALUES(1, 'from', 0, 'a@example.org', 'A');
    INSERT INTO summary_value(item, role, position, value) VALUES(1, 'in-reply-to', 0, 'b@example.org');
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
UPDATE summary SET date = '12 Nov 2026' WHERE component = 'mail'
UPDATE summary SET date = '2026-10-06T08:00:00.000Z' WHERE component = 'mail'
UPDATE summary SET date = '2026-10-06T08:00:00+00:00' WHERE component = 'mail'
UPDATE summary SET size = -1 WHERE component = 'mail'
UPDATE summary SET size = -1 WHERE component = 'file'
UPDATE queue SET attempts = -1
UPDATE summary SET attachment = 7 WHERE component = 'mail'
UPDATE summary SET recurring = 2 WHERE component = 'event'
UPDATE summary SET recurring = -1 WHERE component = 'task'
UPDATE summary SET component = 'note' WHERE item = 1
UPDATE summary SET dtstart = '20261006' WHERE component = 'mail'
UPDATE summary SET sender = 'a@example.org' WHERE component = 'event'
UPDATE summary SET due = '20261006' WHERE component = 'event'
UPDATE summary SET card_kind = 'individual' WHERE component = 'task'
UPDATE summary SET uid = 'x' WHERE component = 'file'
UPDATE summary SET part = '2' WHERE component = 'mail'
UPDATE summary_value SET name = 'B' WHERE role = 'in-reply-to'
UPDATE items SET retained_by = 'imap' WHERE link_id = 'a'
UPDATE items SET retained_at = NULL WHERE link_id = 'r'
UPDATE bindings SET base_present = 0
UPDATE bindings SET base_present = 0, base_object = NULL
UPDATE bindings SET base_present = 0, base_object = NULL, base_revision = NULL, base_flags_known = 1
UPDATE items SET keywords = '$x' WHERE link_id = 'a'
UPDATE items SET flags_known = 1, keywords = ' $x' WHERE link_id = 'a'
UPDATE items SET flags_known = 1, keywords = '$x ' WHERE link_id = 'a'
UPDATE items SET flags_known = 1, keywords = '$x  $y' WHERE link_id = 'a'
UPDATE items SET flags_known = 1, keywords = '$x' || char(9) || '$y' WHERE link_id = 'a'
UPDATE items SET flags_known = 1, keywords = 'caf' || char(233) WHERE link_id = 'a'
UPDATE items SET flags_known = 1, keywords = x'2478' WHERE link_id = 'a'
UPDATE bindings SET base_keywords = '$x'
UPDATE bindings SET base_flags_known = 1, base_keywords = '$x '
UPDATE bindings SET base_flags_known = 1, base_keywords = 'caf' || char(233)
SHAPES
if [ "$("$floor" "$dir/shapes.db" .dump)" != "$shapes" ]; then
    echo "a refused write moved a row on SQLite $version" >&2
    exit 1
fi
# What each column may also hold is taken there: a NULL where one is allowed,
# a size of none, a known flag set's keywords, a base let go whole.
"$floor" "$dir/shapes.db" "PRAGMA foreign_keys = ON;
    UPDATE summary SET date = NULL, size = NULL, attachment = NULL WHERE component = 'mail';
    UPDATE summary SET recurring = NULL WHERE component = 'event'; UPDATE summary_value SET name = NULL WHERE role = 'from';
    UPDATE summary SET recurring = 1 WHERE component = 'task'; UPDATE sources SET covered_since = NULL, round_until = NULL;
    UPDATE receipts SET seq = NULL; UPDATE items SET retained_by = NULL WHERE link_id = 'r'; UPDATE objects SET size = 0;
    UPDATE items SET flags_known = 1, keywords = '\$Junk \\seen ~x' WHERE link_id = 'a';
    UPDATE bindings SET base_flags_known = 1, base_keywords = '\$Junk';
    UPDATE bindings SET base_flags_known = 0, base_keywords = '';
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
    "$1" -separator ' ' "$2" "PRAGMA foreign_keys = ON; EXPLAIN DELETE FROM objects WHERE id = 1;" |
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

# A migration keeps every row on the floor too (§6): the additive one, the
# rebuild with foreign keys off before the transaction and the edit of a
# CHECK, with the rebuild §6 forbids, which loses the rows there silently.
bash "$rehearsal/run.sh" "$root" "$floor"

echo "the store schema loads on SQLite $version, $(wc -l < <("$floor" "$dir/floor.db" "$objects")) objects, every write to its $tables tables compiling, a body's name checked, $refusals mis-shaped writes refused, an object's delete seeking its pointers, its triggers stored as the canonical text writes them and no trusted_schema there"
