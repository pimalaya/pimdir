#!/usr/bin/env bash
# Runs the canonical statements against the canonical schema in the scenarios
# the documents argue from, and asserts the outcome each one promises. Needs
# sqlite3 alone. Every statement is read from queries/ verbatim and bound with
# the CLI's .parameter, so a statement that drifts from its rule fails here.
set -euo pipefail

root="${1:-$PWD}"
dir="$(mktemp -d)"
failures=0

fresh() {
    rm -f "$dir/pimdir.db" "$dir/index.db"
    for migration in "$root"/migrations/storage/*.sql; do
        sqlite3 "$dir/pimdir.db" "BEGIN; $(cat "$migration") PRAGMA user_version = 1; COMMIT;"
    done
    sql "INSERT INTO store_meta(id, format, version, hash_algo, created_at) VALUES(1, 'pimdir', 1, 'blake3', 'now');"
}

# sql <statement...>: runs literal SQL with foreign keys on.
sql() {
    sqlite3 "$dir/pimdir.db" "PRAGMA foreign_keys = ON; $*"
}

# run <profile/name> [:param=literal...]: runs one canonical statement, bound.
run() {
    local file="$1"; shift
    {
        echo "PRAGMA foreign_keys = ON;"
        for binding in "$@"; do
            echo ".parameter set ${binding%%=*} ${binding#*=}"
        done
        cat "$root/queries/storage/$file.sql"
    } | sqlite3 "$dir/pimdir.db"
}

# fails <profile/name> [:param=literal...]: the statement must be refused.
fails() {
    if run "$@" >/dev/null 2>&1; then
        return 1
    fi
}

expect() {
    local label="$1" got="$2" want="$3"
    if [ "$got" != "$want" ]; then
        echo "$label: expected [$want], got [$got]" >&2
        failures=$((failures + 1))
    fi
}

collection() {
    run owner/set_collection_kind ":collection='$1'" ":account=${2:-NULL}" ":kind='message/rfc822'"
}

item() {
    run owner/insert_item ":collection='$1'" ":link_id='$2'" ":seq=$3" ":flags='[]'" \
        ":object_hash=${4:-NULL}" ":sort_key=''" ":level=2" ":deleted=0" ":conflicted=0" ":conflict_object=NULL"
}

object() {
    run queue/store_object ":hash='$1'" ":size=1"
}

# --- The change feed (§4.5) ------------------------------------------------

fresh
collection INBOX
item INBOX a 1
cursor="$(run read/load_change_cursor | cut -d'|' -f1)"
item INBOX b 2
expect "feed: the first stamp after the cursor is above it" \
    "$(run read/list_items_changed_since ":since=$cursor" ":limit=10" | cut -d'|' -f2)" "b"

run owner/stamp_item ":collection='INBOX'" ":link_id='a'"
item INBOX c 3
expect "feed: stamps are unique after a stamp request" \
    "$(sql "SELECT count(*) - count(DISTINCT changed) FROM items;")" "0"
expect "feed: a stamp request draws the counter" \
    "$(sql "SELECT changed < (SELECT next_change FROM store_meta) AND changed > 0 FROM items WHERE link_id = 'a';")" "1"

cursor="$(run read/load_change_cursor | cut -d'|' -f1)"
run owner/rename_collection ":collection='INBOX'" ":new_id='Archive'"
expect "feed: a rename restamps every item under the new id" \
    "$(run read/list_items_changed_since ":since=$cursor" ":limit=10" | cut -d'|' -f1 | sort -u)" "Archive"

# --- The trash view and the terminal states (§11) ----------------------------

fresh
collection INBOX
item INBOX a 1
item INBOX b 2
run owner/insert_binding ":collection='INBOX'" ":link_id='b'" ":source='imap'" ":handle='10'" \
    ":base_flags='[]'" ":base_object=NULL" ":base_revision=NULL" ":base_present=1" \
    ":conflicted=0" ":conflict_revision=NULL" ":conflict_object=NULL" ":shared_object=NULL"
run owner/retain_item ":collection='INBOX'" ":link_id='a'" ":source='imap'"
sql "UPDATE items SET deleted = 1 WHERE link_id = 'b';"
expect "trash: a retained row and a held tombstone are both listed" \
    "$(run read/list_retained_page ":collection='INBOX'" ":after=0" ":limit=10" | cut -d'|' -f1 | tr '\n' ' ')" "1 2 "
expect "trash: a held tombstone is not purged" \
    "$(run owner/purge_item ":collection='INBOX'" ":seq=2" | wc -l)" "0"
expect "trash: retention implies deleted" \
    "$(sql "UPDATE items SET deleted = 0 WHERE link_id = 'a';" 2>&1 | grep -c CHECK)" "1"
expect "conflict: a diverging body needs the flag" \
    "$(sql "UPDATE items SET conflict_object = 'x' WHERE link_id = 'b';" 2>&1 | grep -c 'constraint')" "1"

# --- A move purges only when the holder carries the body (§11) ---------------

fresh
collection INBOX
collection Archive
object h1
object h2
item INBOX a 1 "'h1'"
item Archive a 1 "'h1'"
expect "move: a holder with the same body is a move" \
    "$(run owner/held_elsewhere ":collection='INBOX'" ":link_id='a'" ":object='h1'")" "1"
sql "UPDATE items SET object_hash = 'h2' WHERE collection = 'Archive';"
expect "move: a holder with another body is not" \
    "$(run owner/held_elsewhere ":collection='INBOX'" ":link_id='a'" ":object='h1'")" ""
sql "UPDATE items SET object_hash = NULL WHERE collection = 'Archive';"
expect "move: a bodiless holder does not take the only body" \
    "$(run owner/held_elsewhere ":collection='INBOX'" ":link_id='a'" ":object='h1'")" ""
expect "move: a bodiless retiring row is held by any holder" \
    "$(run owner/held_elsewhere ":collection='INBOX'" ":link_id='a'" ":object=NULL")" "1"

# --- The producer's pin and the collector (§5, §15) --------------------------

fresh
collection INBOX
object h1
run queue/pin_object ":hash='h1'"
run queue/enqueue_action ":producer='p'" ":collection='INBOX'" ":action='add'" ":payload='{\"v\":1}'" ":object_hash='h1'"
expect "queue: the enqueue pins the body" "$(sql "SELECT refcount FROM objects WHERE hash = 'h1';")" "1"
run owner/recompute_refcounts
expect "queue: the recompute agrees" "$(sql "SELECT refcount FROM objects WHERE hash = 'h1';")" "1"
run owner/delete_garbage_objects
expect "queue: the collector spares it" "$(sql "SELECT count(*) FROM objects;")" "1"
pin="$(run owner/cancel_action ":id=1")"
run owner/release_pins ":hashes='[\"$pin\"]'"
expect "queue: cancelling releases the pin" "$(sql "SELECT refcount FROM objects WHERE hash = 'h1';")" "0"
purges="$(sql "SELECT purges FROM store_meta;")"
run owner/delete_garbage_objects
expect "feed: a collected object counts as a purge" "$(sql "SELECT purges FROM store_meta;")" "$((purges + 1))"

# --- The drain order and the rename of a target (§14, §15) -------------------

fresh
collection INBOX
collection Archive
run queue/enqueue_action ":producer='p'" ":collection='INBOX'" ":action='move'" ":payload='{\"v\":1,\"seq\":5,\"to\":\"Archive\"}'" ":object_hash=NULL"
run queue/enqueue_action ":producer='p'" ":collection='Archive'" ":action='set-flags'" ":payload='{\"v\":1,\"seq\":5,\"flags\":[]}'" ":object_hash=NULL"
expect "queue: the drain is store-wide in append order" \
    "$(run owner/list_pending_actions | cut -d'|' -f5 | tr '\n' ' ')" "move set-flags "
run owner/rename_queue_targets ":collection='Archive'" ":new_id='Archive-2026'"
run owner/rename_collection ":collection='Archive'" ":new_id='Archive-2026'"
expect "queue: a rename follows into a pending move" \
    "$(sql "SELECT json_extract(payload, '\$.to') FROM queue WHERE action = 'move';")" "Archive-2026"

# --- Removing a collection settles its pins (§14) ----------------------------

fresh
collection INBOX
object h1
item INBOX a 1 "'h1'"
run owner/adjust_refcount ":hash='h1'" ":delta=1"
run owner/delete_collection ":collection='INBOX'"
run owner/recompute_refcounts
expect "collection: the cascade's pins are settled by the recompute" \
    "$(sql "SELECT refcount FROM objects WHERE hash = 'h1';")" "0"
expect "collection: the cascade counts its rows as purges" "$(sql "SELECT purges FROM store_meta;")" "1"

if [ "$failures" -gt 0 ]; then
    echo "$failures invariant(s) broken" >&2
    exit 1
fi

echo "every invariant scenario holds"
