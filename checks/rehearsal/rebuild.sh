#!/usr/bin/env bash
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Prints a rehearsal migration, never shipped under migrations/, rebuilding
# one table of a store as STORAGE.md §6 asks of a script that rebuilds: the
# triggers and views of other tables naming the table dropped first, the new
# table created under a temporary name, the rows copied by named columns, the
# old table dropped and the new one renamed, the AUTOINCREMENT sequence kept,
# the table's indexes and triggers created again, then the dependents. The
# table's text is read off the store, where a shipped migration writes it
# out, so the rehearsal follows 0001_init.sql while it is still edited.
#
# Usage: rebuild.sh <sqlite3> <database> <table> [sed expression on its text]
set -euo pipefail

shell="$1" db="$2" table="$3" edit="${4:-}"

ask() {
    "$shell" "$db" "$1"
}

text="$(ask "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = '$table';")"
columns="$(ask "SELECT group_concat(name, ', ') FROM pragma_table_info('$table');")"
# What the drop takes: the table's own indexes and triggers. What the rename
# would trip on: a trigger or a view of another table naming this one.
own="SELECT sql || ';' FROM sqlite_master
     WHERE tbl_name = '$table' AND type IN ('index', 'trigger') AND sql IS NOT NULL
     ORDER BY type, name;"
dependents="FROM sqlite_master
     WHERE tbl_name != '$table' AND type IN ('trigger', 'view')
       AND (sql LIKE '% $table %' OR sql LIKE '% $table' || char(10) || '%'
            OR sql LIKE '% $table;%' OR sql LIKE '% $table)%'
            OR sql LIKE '% $table(%')
     ORDER BY type, name"

ask "SELECT 'DROP ' || upper(type) || ' ' || name || ';' $dependents;"
sed "1s/CREATE TABLE $table /CREATE TABLE ${table}_rebuilt /${edit:+;$edit}" <<<"$text;"
cat <<SQL
INSERT INTO ${table}_rebuilt($columns) SELECT $columns FROM $table;
CREATE TEMP TABLE rehearsal_sequence AS
SELECT seq FROM sqlite_sequence WHERE name = '$table';
DROP TABLE $table;
ALTER TABLE ${table}_rebuilt RENAME TO $table;
DELETE FROM sqlite_sequence
WHERE name = '$table' AND EXISTS (SELECT 1 FROM temp.rehearsal_sequence);
INSERT INTO sqlite_sequence(name, seq)
SELECT '$table', seq FROM temp.rehearsal_sequence;
DROP TABLE temp.rehearsal_sequence;
SQL
ask "$own"
ask "SELECT sql || ';' $dependents;"
