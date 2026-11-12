#!/bin/sh
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Rehearses on a scratch store the migration STORAGE.md §6 foresees and no
# check runs (audit-2026-11-12, line V1): a fifth kind added to collections,
# first by rebuilding the table under the runner as §6 step 3 states it (one
# transaction, foreign keys on), then with foreign keys off before the
# transaction, then by editing the CHECK under writable_schema.
#
# Usage: sh rebuild.sh <sqlite3> [repository root]
#
# Prints, for each route, the rows left and what the integrity checks say.
# Run it once with a current sqlite3 and once with the 3.18.2 floor build of
# flake.nix. Writes under a directory of its own in $TMPDIR, removed on exit.
set -u

sqlite="$1"
root="${2:-.}"
dir="$(mktemp -d "${TMPDIR:-/tmp}/pimdir-rebuild.XXXXXX")"
trap 'rm -rf "$dir"' EXIT

counts="SELECT 'user_version', (SELECT user_version FROM pragma_user_version)
UNION ALL SELECT 'collections', count(*) FROM collections
UNION ALL SELECT 'items', count(*) FROM items
UNION ALL SELECT 'flags', count(*) FROM placement_flag
UNION ALL SELECT 'mail_summary', count(*) FROM mail_summary;"
owned="SELECT count(*) FROM sqlite_master WHERE tbl_name = 'collections'
AND type IN ('trigger', 'index') AND sql IS NOT NULL;"
checks="PRAGMA foreign_keys = ON; PRAGMA foreign_key_check; PRAGMA integrity_check;"
stamp="PRAGMA user_version = 2; UPDATE store_meta SET version = 2,
read_version = 2, produce_version = 1, format_version = 'storage-v2' WHERE id = 1;"

report() {
    echo "$1: $("$sqlite" "$2" "$counts" 2>&1 | tr '\n' ' ')"
    echo "$1 checks: $("$sqlite" "$2" "$checks" 2>&1 | head -3 | tr '\n' ' ')"
    echo "$1 indexes and triggers of collections: $("$sqlite" "$2" "$owned" 2>&1)"
}

echo "sqlite $("$sqlite" :memory: 'SELECT sqlite_version()')"

"$sqlite" "$dir/base.db" "BEGIN; $(cat "$root/migrations/storage/0001_init.sql")
PRAGMA user_version = 1; COMMIT;" || echo "the schema failed to load"
"$sqlite" "$dir/base.db" "PRAGMA foreign_keys = ON;
INSERT INTO store_meta(id, format, format_version, version, read_version,
    produce_version, store_id, incarnation, hash_algo, created_at, derivation)
VALUES (1, 'pimdir', 'storage-v1', 1, 1, 1, lower(hex(randomblob(16))), 1,
    'blake3', strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), 3);
INSERT INTO collections(id, kind, name) VALUES ('INBOX', 'message/rfc822', 'INBOX');
INSERT INTO items(collection, link_id, seq, flags_known, marks, level)
VALUES ('INBOX', 'a@x', 1, 1, 1, 1), ('INBOX', 'b@x', 2, 1, 0, 1);
INSERT INTO placement_flag(item, flag) VALUES (1, '\$label');
INSERT INTO mail_summary(item, subject) VALUES (1, 'hello');"
report "base" "$dir/base.db"

ddl="$("$sqlite" "$dir/base.db" "SELECT sql FROM sqlite_master WHERE name = 'collections';" |
    sed "s/CREATE TABLE collections/CREATE TABLE collections_new/;
         s/'application\/octet-stream'/'application\/octet-stream', 'text\/x-note'/")"
cols="$("$sqlite" "$dir/base.db" "SELECT group_concat(name, ', ') FROM pragma_table_info('collections');")"
rebuild="$ddl;
INSERT INTO collections_new($cols) SELECT $cols FROM collections;
DROP TABLE collections;
ALTER TABLE collections_new RENAME TO collections;
$stamp"

echo "--- A: the rebuild in one transaction, foreign keys on (§6 step 3)"
cp "$dir/base.db" "$dir/a.db"
"$sqlite" "$dir/a.db" "PRAGMA foreign_keys = ON; BEGIN; $rebuild COMMIT;" 2>&1 | head -3
report "A" "$dir/a.db"

echo "--- B: the rebuild with foreign keys off before the transaction"
cp "$dir/base.db" "$dir/b.db"
"$sqlite" "$dir/b.db" "PRAGMA foreign_keys = OFF; BEGIN; $rebuild
PRAGMA foreign_key_check; COMMIT;" 2>&1 | head -3
report "B" "$dir/b.db"

echo "--- C: the CHECK edited under writable_schema, foreign keys on"
cp "$dir/base.db" "$dir/c.db"
version="$("$sqlite" "$dir/c.db" 'PRAGMA schema_version;')"
"$sqlite" "$dir/c.db" "PRAGMA foreign_keys = ON; BEGIN;
PRAGMA writable_schema = ON;
UPDATE sqlite_master SET sql = replace(sql, '''application/octet-stream''))',
    '''application/octet-stream'', ''text/x-note''))')
WHERE type = 'table' AND name = 'collections';
PRAGMA schema_version = $((version + 1));
PRAGMA writable_schema = OFF;
$stamp COMMIT;" 2>&1 | head -3
report "C" "$dir/c.db"
echo "C a fifth kind: $("$sqlite" "$dir/c.db" "PRAGMA foreign_keys = ON;
INSERT INTO collections(id, kind, name) VALUES ('Notes', 'text/x-note', 'Notes');
SELECT count(*) FROM collections;" 2>&1 | tr '\n' ' ')"
echo "C a sixth kind: $("$sqlite" "$dir/c.db" "PRAGMA foreign_keys = ON;
INSERT INTO collections(id, kind, name) VALUES ('Z', 'text/x-zzz', 'Z');" 2>&1 | head -1)"
