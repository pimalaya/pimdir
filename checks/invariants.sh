#!/usr/bin/env bash
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Runs the canonical statements against the canonical schema in the scenarios
# the documents argue from, and asserts the outcome each one promises. Needs
# sqlite3 alone. Every statement is read from queries/ verbatim and bound with
# the CLI's .parameter, so a statement that drifts from its rule fails here.
# Every statement under queries/ runs in some scenario, or is waived with its
# reason in the file the second argument names (checks/waivers.txt), so no
# statement regresses unseen.
set -euo pipefail

root="${1:-$PWD}"
waivers="${2:-$root/checks/waivers.txt}"
dir="$(mktemp -d)"
trap 'rm -rf "$dir"' EXIT
failures=0

# statement <part/profile/name>: a statement's text, read from queries/, and
# recorded as run for the gate at the end. A plan reads the text without it.
statement() {
    echo "$1" >> "$dir/ran"
    cat "$root/queries/$1.sql"
}

# Every connection that writes sets secure_delete (STORAGE.md §11.5), which an
# erasure scenario turns OFF to show what it zeroes. With untrusted 1, a
# connection also runs as a program opening a store it did not create does
# (§18): trusted_schema off, the defensive flag on. Each pragma answers its
# value, which the output drops.
secure_delete=ON
untrusted=0
prelude() {
    echo ".output /dev/null"
    echo "PRAGMA secure_delete = $secure_delete;"
    if [ "$untrusted" = 1 ]; then
        echo ".dbconfig defensive on"
        echo "PRAGMA trusted_schema = OFF;"
    fi
    echo ".output"
}

fresh() {
    rm -f "$dir/pimdir.db" "$dir/index.db"
    for migration in "$root"/migrations/storage/*.sql; do
        sqlite3 "$dir/pimdir.db" "BEGIN; $(cat "$migration")"$'\n'"PRAGMA user_version = 1; COMMIT;"
    done
    run owner/init_store_meta ":version=1" ":derivation=3"
}

# sql <statement...>: runs literal SQL with foreign keys on.
sql() {
    local lines
    mapfile -t lines < <(prelude)
    sqlite3 "$dir/pimdir.db" "${lines[@]}" "PRAGMA foreign_keys = ON; $*"
}

# The system flags and their bits (STORAGE.md §13), as rows.
system="WITH system(bit, name) AS (VALUES (1, '\Seen'), (2, '\Answered'), (4, '\Flagged'), (8, '\Draft'), (16, '\Deleted'))"

# flags <collection> <link_id>, base_flags <collection> <link_id> <source>: a
# set, its bits and its rows, sorted, joined with spaces.
flags() {
    sql "$system SELECT group_concat(flag, ' ') FROM (
         SELECT name AS flag FROM system, items i
         WHERE i.collection = '$1' AND i.link_id = '$2' AND i.marks & bit
         UNION ALL
         SELECT f.flag FROM placement_flag f JOIN items i ON i.id = f.item
         WHERE i.collection = '$1' AND i.link_id = '$2' ORDER BY flag);"
}

base_flags() {
    sql "$system SELECT group_concat(flag, ' ') FROM (
         SELECT name AS flag FROM system, bindings b JOIN items i ON i.id = b.item
         WHERE i.collection = '$1' AND i.link_id = '$2' AND b.source = '$3' AND b.base_marks & bit
         UNION ALL
         SELECT g.flag FROM binding_base_flag g JOIN items i ON i.id = g.item
         WHERE i.collection = '$1' AND i.link_id = '$2' AND g.source = '$3' ORDER BY flag);"
}

# marks <'["a","b"]'>: the bits a set's system flags take (§13), and keywords
# <'["a","b"]'>: the slot rows of the set's other flags.
marks() {
    sqlite3 :memory: "SELECT coalesce(sum(CASE value WHEN '\Seen' THEN 1 WHEN '\Answered' THEN 2 WHEN '\Flagged' THEN 4 WHEN '\Draft' THEN 8 WHEN '\Deleted' THEN 16 ELSE 0 END), 0) FROM (SELECT DISTINCT value FROM json_each($1));"
}

keywords() {
    echo "INSERT INTO temp.param(slot, position, value) SELECT 'flags', key, value FROM json_each($1)
          WHERE value NOT IN ('\Seen', '\Answered', '\Flagged', '\Draft', '\Deleted');"
}

# params <slot> <'["a","b"]'>: fills one slot of the list parameters' table
# (create_param) the way bind_param does, one row per value in order. The
# harness spells a list as JSON for brevity; the canonical text reads none.
params() {
    echo "INSERT INTO temp.param(slot, position, value) SELECT '$1', key, value FROM json_each($2);"
}

# run <profile/name> [:param=literal...]: runs one canonical statement, bound.
# A list parameter is written as a JSON array literal, `:links='["a"]'`, and
# bound through its slot (§4.4). A `:flags` or `:base_flags` list on a row
# write binds the set as known and writes it after the row with retain_flags
# and add_flags (or their base twins), NULL binding it unknown. A
# `.name=value` binding is a dot command.
bindings() {
    local binding name value
    statement storage/read/create_param
    for binding in "$@"; do
        name="${binding%%=*}"
        value="${binding#*=}"
        case "$name:$value" in
            :flags:NULL)
                echo ".parameter set :flags_known 0"
                echo ".parameter set :marks 0" ;;
            :base_flags:NULL)
                echo ".parameter set :base_flags_known 0"
                echo ".parameter set :base_marks 0" ;;
            ":flags:'["*)
                echo ".parameter set :flags_known 1"
                echo ".parameter set :marks $(marks "$value")"
                keywords "$value" ;;
            ":base_flags:'["*)
                echo ".parameter set :base_flags_known 1"
                echo ".parameter set :base_marks $(marks "$value")"
                keywords "$value" ;;
            .*)
                echo "$name $value" ;;
            *":'["*)
                params "${name#:}" "$value" ;;
            *)
                echo ".parameter set $name $value" ;;
        esac
    done
}

run() {
    local file="$1"; shift
    local after=""
    case " $* " in
        *" :flags='["*) after=flags ;;
        *" :base_flags='["*) after=base_flags ;;
    esac
    {
        prelude
        echo "PRAGMA foreign_keys = ON;"
        bindings "$@"
        statement "storage/$file"
        case "$after" in
            flags) statement storage/owner/retain_flags; statement storage/owner/add_flags ;;
            base_flags) statement storage/owner/retain_base_flags; statement storage/owner/add_base_flags ;;
        esac
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


# plan <profile/name> [:param=literal...]: the statement's query plan, bound.
plan() {
    local file="$1"; shift
    {
        bindings "$@"
        echo "EXPLAIN QUERY PLAN"
        cat "$root/queries/storage/$file.sql"
    } | sqlite3 "$dir/pimdir.db"
}
# trigger_plan <trigger> [:param=literal...]: the plan of a trigger's one
# statement, read back from the schema, each OLD.x bound as :old_x.
trigger_plan() {
    local name="$1"; shift
    local body
    body="$(sql "SELECT sql FROM sqlite_schema WHERE name = '$name';" | sed -n '/^BEGIN$/,/^END$/p' | sed '1d;$d;s/OLD\./:old_/g')"
    {
        for binding in "$@"; do
            echo ".parameter set ${binding%%=*} ${binding#*=}"
        done
        echo "EXPLAIN QUERY PLAN"
        echo "$body"
    } | sqlite3 "$dir/pimdir.db"
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

# name <label>: a body's name for a scenario, standing in for a BLAKE3 one
# (§5): the label, its digits outside base32's 2-7 spelled as the letters they
# resemble, padded with `a` to 52 characters, so the schema's CHECK on
# objects.hash takes it and each label keeps a name of its own. The scenarios
# refer to a body by the variable of its label, $h1 for h1.
name() {
    local label
    label="$(tr 0189 olsg <<< "$1")"
    while [ "${#label}" -lt 52 ]; do
        label="${label}a"
    done
    echo "$label"
}

for label in c1 c2 h1 h2 h3 h4 h5 h6 h7 h8 h9 hb hc he hj hn ht hx m1 m9; do
    printf -v "$label" '%s' "$(name "$label")"
done

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
purges="$(run read/load_change_cursor | cut -d'|' -f2)"
run owner/rename_collection ":collection='INBOX'" ":new_id='Archive'"
expect "feed: a rename restamps every item under the new id" \
    "$(run read/list_items_changed_since ":since=$cursor" ":limit=10" | cut -d'|' -f1 | sort -u)" "Archive"
expect "feed: a rename counts in purges, the old keys gone as a purged row's" \
    "$(run read/load_change_cursor | cut -d'|' -f2)" "$((purges + 1))"

# --- Flags are rows, read as a set (§13, §14.1) ------------------------------

fresh
collection INBOX
item INBOX a 1
item INBOX u 2
run owner/update_item ":collection='INBOX'" ":link_id='u'" ":flags=NULL" ":object_hash=NULL" ":sort_key=''" \
    ":level=2" ":deleted=0" ":conflicted=0" ":conflict_object=NULL"
write_flags() {
    run owner/update_item ":collection='INBOX'" ":link_id='a'" ":flags=$1" ":object_hash=NULL" ":sort_key=''" \
        ":level=2" ":deleted=0" ":conflicted=0" ":conflict_object=NULL"
}
expect "flags: known-empty reads as '', unknown as NULL" \
    "$(run read/get_item ":collection='INBOX'" ":seq=1" ".nullvalue=NULL" | cut -d'|' -f3)|$(run read/get_item ":collection='INBOX'" ":seq=2" ".nullvalue=NULL" | cut -d'|' -f3)" "|NULL"
before="$(sql "SELECT changed FROM items WHERE link_id = 'a';")"
write_flags "'[\"\\\\Seen\",\"\$label\"]'"
expect "flags: a set is its rows, read joined with spaces, and moves the stamp" \
    "$(run read/get_item ":collection='INBOX'" ":seq=1" | cut -d'|' -f3 | tr ' ' '\n' | LC_ALL=C sort | tr '\n' ' ')|$(sql "SELECT changed > $before FROM items WHERE link_id = 'a';")" \
    "\$label \\Seen |1"
before="$(sql "SELECT changed FROM items WHERE link_id = 'a';")"
write_flags "'[\"\$label\",\"\\\\Seen\",\"\\\\Seen\"]'"
expect "flags: a set written again as it was stamps nothing, a flag named twice once" \
    "$(sql "SELECT changed = $before FROM items WHERE link_id = 'a';")|$(flags INBOX a)" "1|\$label \\Seen"
write_flags "'[\"\\\\Seen\"]'"
expect "flags: a flag the set no longer names goes and moves the stamp" \
    "$(sql "SELECT changed > $before FROM items WHERE link_id = 'a';")|$(flags INBOX a)" "1|\\Seen"
expect "flags: an unknown set refuses a flag" \
    "$(sql "INSERT INTO placement_flag(item, flag) VALUES((SELECT id FROM items WHERE collection = 'INBOX' AND link_id = 'u'), '\\Seen');" 2>&1 | grep -c 'flags unknown')" "1"
expect "flags: a flag holding a space or a control character, or empty, is refused" \
    "$(sql "INSERT INTO placement_flag VALUES((SELECT id FROM items WHERE collection = 'INBOX' AND link_id = 'a'), 'two words');" 2>&1 | grep -c CHECK)$(sql "INSERT INTO placement_flag VALUES((SELECT id FROM items WHERE collection = 'INBOX' AND link_id = 'a'), 'tab' || char(9));" 2>&1 | grep -c CHECK)$(sql "INSERT INTO placement_flag VALUES((SELECT id FROM items WHERE collection = 'INBOX' AND link_id = 'a'), '');" 2>&1 | grep -c CHECK)" "111"
write_flags NULL
expect "flags: a set becoming unknown loses its rows" \
    "$(sql "SELECT count(*) FROM placement_flag WHERE item IN (SELECT id FROM items WHERE link_id = 'a');")|$(run read/get_item ":collection='INBOX'" ":seq=1" | cut -d'|' -f3)" "0|"
write_flags "'[\"\\\\Flagged\"]'"
run owner/rename_collection ":collection='INBOX'" ":new_id='Archive'"
expect "flags: a rename carries them, a purge takes them" \
    "$(flags Archive a)|$(sql "DELETE FROM items WHERE link_id = 'a'; SELECT count(*) FROM placement_flag;")" "\\Flagged|0"

fresh
collection INBOX
item INBOX a 1
run owner/insert_binding ":collection='INBOX'" ":link_id='a'" ":source='imap'" ":handle='10'" \
    ":base_flags='[\"\\\\Seen\"]'" ":base_object=NULL" ":base_revision=NULL" ":base_present=1" \
    ":conflicted=0" ":conflict_revision=NULL" ":conflict_object=NULL" ":shared_object=NULL"
expect "base flags: a base set is its rows, read joined" \
    "$(run read/list_item_bindings ":collection='INBOX'" ":link_id='a'" | cut -d'|' -f4)" "\\Seen"
run owner/update_binding ":collection='INBOX'" ":link_id='a'" ":source='imap'" ":base_flags=NULL" ":base_object=NULL" \
    ":base_revision=NULL" ":base_present=1" ":conflicted=0" ":conflict_revision=NULL" ":conflict_object=NULL" ":shared_object=NULL"
expect "base flags: an unknown base holds no row and refuses one" \
    "$(base_flags INBOX a imap)|$(sql "INSERT INTO binding_base_flag VALUES((SELECT id FROM items WHERE collection = 'INBOX' AND link_id = 'a'), 'imap', '\\Seen');" 2>&1 | grep -c 'base flags unknown')" "|1"

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
object "$h1"
object "$h2"
item INBOX a 1 "'$h1'"
item Archive a 1 "'$h1'"
expect "move: a holder with the same body is a move" \
    "$(run owner/held_elsewhere ":collection='INBOX'" ":link_id='a'" ":object='$h1'")" "1"
sql "UPDATE items SET object_hash = '$h2' WHERE collection = 'Archive';"
expect "move: a holder with another body is not" \
    "$(run owner/held_elsewhere ":collection='INBOX'" ":link_id='a'" ":object='$h1'")" ""
sql "UPDATE items SET object_hash = NULL WHERE collection = 'Archive';"
expect "move: a bodiless holder does not take the only body" \
    "$(run owner/held_elsewhere ":collection='INBOX'" ":link_id='a'" ":object='$h1'")" ""
expect "move: a bodiless retiring row is held by any holder" \
    "$(run owner/held_elsewhere ":collection='INBOX'" ":link_id='a'" ":object=NULL")" "1"

# --- The producer's pin and the collector (§5, §15) --------------------------

fresh
collection INBOX
object "$h1"
run queue/pin_object ":hash='$h1'"
run queue/enqueue_action ":producer='p'" ":collection='INBOX'" ":action='add'" ":payload='{\"v\":1,\"flags\":[],\"object\":\"$h1\"}'" ":object_hash='$h1'"
expect "queue: the enqueue pins the body" "$(sql "SELECT refcount FROM objects WHERE hash = '$h1';")" "1"
run owner/recompute_refcounts
expect "queue: the recompute agrees" "$(sql "SELECT refcount FROM objects WHERE hash = '$h1';")" "1"
run owner/delete_garbage_objects
expect "queue: the collector spares it" "$(sql "SELECT count(*) FROM objects;")" "1"
pin="$(run owner/cancel_action ":id=1")"
run owner/release_pins ":hashes='[\"$pin\"]'"
expect "queue: cancelling releases the pin" "$(sql "SELECT refcount FROM objects WHERE hash = '$h1';")" "0"
purges="$(sql "SELECT purges FROM store_meta;")"
run owner/delete_garbage_objects
expect "feed: a collected object counts as a purge" "$(sql "SELECT purges FROM store_meta;")" "$((purges + 1))"

# --- A hash is one algorithm's name, never a path (§5, §13) -----------------

fresh
collection INBOX
# stores <name>: S when store_object takes the name, R when it is refused.
stores() {
    if run queue/store_object ":hash='$1'" ":size=1" 2>/dev/null; then echo -n S; else echo -n R; fi
}
expect "blob: a name is 52 characters of lowercase base32; ../x, an uppercase, a short, a long, a 1, a padding and a separator are refused" \
    "$(for hash in "$h2" ../x "$(tr a-z A-Z <<< "$h1")" "${h1:0:26}" "${h1}a" "${h1:0:51}1" "${h1:0:51}=" \
           "${h1:0:2}/${h1:3}"; do stores "$hash"; done)" "SRRRRRRR"
run queue/store_object ":hash='../x'" ":size=1" 2>/dev/null || true
run queue/pin_object ":hash='../x'" 2>/dev/null || true
# A malformed payload: its body named by a path, which its schema refuses as
# the name's CHECK does.
run queue/enqueue_action ":producer='p'" ":collection='INBOX'" ":action='add'" ":payload='{\"v\":1,\"flags\":[],\"object\":\"../x\"}'" \
    ":object_hash='../x'" 2>/dev/null || true
expect "blob: a producer storing ../x stores, pins and enqueues nothing, so no queued body names a path" \
    "$(sql "SELECT count(*) FROM queue;")|$(sql "SELECT group_concat(hash) FROM objects;")" "0|$h2"
expect "blob: a store names BLAKE3, and no other algorithm" \
    "$(run read/load_store_meta | cut -d'|' -f3)|$(sql "UPDATE store_meta SET hash_algo = 'sha256-128';" 2>&1 | grep -c 'CHECK')" \
    "blake3|1"

# --- The agreed body stays pinned until its binding agrees again (§5) ------

fresh
run owner/set_collection_kind ":collection='Cards'" ":account=NULL" ":kind='text/vcard'"
object "$c1"
object "$c2"
item Cards card 1 "'$c2'"
run owner/insert_binding ":collection='Cards'" ":link_id='card'" ":source='a'" ":handle='a.vcf'" \
    ":base_flags='[]'" ":base_object='$c2'" ":base_revision='r2'" ":base_present=1" \
    ":conflicted=0" ":conflict_revision=NULL" ":conflict_object=NULL" ":shared_object='$c2'"
run owner/insert_binding ":collection='Cards'" ":link_id='card'" ":source='b'" ":handle='b.vcf'" \
    ":base_flags='[]'" ":base_object=NULL" ":base_revision='r9'" ":base_present=1" \
    ":conflicted=0" ":conflict_revision=NULL" ":conflict_object=NULL" ":shared_object='$c1'"
run owner/recompute_refcounts
expect "shared: the body a binding last agreed with is counted, alone" \
    "$(sql "SELECT refcount FROM objects WHERE hash = '$c1';")|$(run owner/list_garbage_objects)" "1|"
run owner/set_collection_kind ":collection='Emptied'" ":account=NULL" ":kind='text/vcard'"
item Emptied card 1
run owner/insert_binding ":collection='Emptied'" ":link_id='card'" ":source='a'" ":handle='e.vcf'" \
    ":base_flags='[]'" ":base_object=NULL" ":base_revision='r2'" ":base_present=1" \
    ":conflicted=0" ":conflict_revision=NULL" ":conflict_object=NULL" ":shared_object='$c1'"
expect "shared: a collection holding only an agreed body holds an object" \
    "$(run owner/collection_holds_objects ":collection='Emptied'")" "1"
expect "shared: the agreed body cannot be deleted under it" \
    "$(sql "DELETE FROM objects WHERE hash = '$c1';" 2>&1 | grep -c 'FOREIGN KEY')" "1"
run owner/delete_collection ":collection='Emptied'"
run owner/update_binding ":collection='Cards'" ":link_id='card'" ":source='b'" \
    ":base_flags='[]'" ":base_object='$c2'" ":base_revision='r10'" ":base_present=1" \
    ":conflicted=0" ":conflict_revision=NULL" ":conflict_object=NULL" ":shared_object='$c2'"
run owner/recompute_refcounts
expect "shared: once the binding agrees again, the old body falls to the collector" \
    "$(run owner/list_garbage_objects)|$(sql "SELECT refcount FROM objects WHERE hash = '$c2';")" "$c1|5"

# --- A performed intent replaced by the change it leaves (§15.5) ------------

fresh
collection Sent
object "$m1"
run queue/pin_object ":hash='$m1'"
run queue/enqueue_action ":producer='p'" ":collection='Sent'" ":action='submit'" ":payload='{\"v\":1,\"source\":\"smtp\",\"from\":\"alice@example.org\",\"rcpts\":[\"bob@example.org\"],\"copy\":\"Sent\"}'" ":object_hash='$m1'"
run queue/pin_object ":hash='$m1'"
run queue/enqueue_action ":producer='owner'" ":collection='Sent'" ":action='add'" ":payload='{\"v\":1,\"flags\":[\"\\\\Seen\"],\"object\":\"$m1\"}'" ":object_hash='$m1'"
pin="$(run owner/cancel_action ":id=1")"
run owner/release_pins ":hashes='[\"$pin\"]'"
run owner/delete_garbage_objects
expect "replace: the copy keeps the body the intent pinned" \
    "$(sql "SELECT refcount FROM objects WHERE hash = '$m1';")$(sql "SELECT action FROM queue;")" "1add"

# --- The drain order and the rename of a target (§14, §15) -------------------

fresh
collection INBOX
collection Archive
run queue/enqueue_action ":producer='p'" ":collection='INBOX'" ":action='move'" ":payload='{\"v\":1,\"seq\":5,\"to\":\"Archive\"}'" ":target_collection='Archive'" ":object_hash=NULL"
run queue/enqueue_action ":producer='p'" ":collection='Archive'" ":action='set-flags'" ":payload='{\"v\":1,\"seq\":5,\"flags\":[]}'" ":object_hash=NULL"
expect "queue: the drain is store-wide in append order" \
    "$(run owner/list_pending_actions | cut -d'|' -f5 | tr '\n' ' ')" "move set-flags "
run owner/rename_queue_targets ":collection='Archive'" ":new_id='Archive-2026'"
run owner/rename_collection ":collection='Archive'" ":new_id='Archive-2026'"
expect "queue: a rename follows into a pending move" \
    "$(sql "SELECT target_collection FROM queue WHERE action = 'move';")" "Archive-2026"

# --- Removing a collection settles its pins (§14) ----------------------------

fresh
collection INBOX
object "$h1"
item INBOX a 1 "'$h1'"
run owner/adjust_refcount ":hash='$h1'" ":delta=1"
run owner/delete_collection ":collection='INBOX'"
run owner/recompute_refcounts
expect "collection: the cascade's pins are settled by the recompute" \
    "$(sql "SELECT refcount FROM objects WHERE hash = '$h1';")" "0"
expect "collection: the cascade counts its rows as purges" "$(sql "SELECT purges FROM store_meta;")" "1"
collection Outbox
object "$m9"
run queue/pin_object ":hash='$m9'"
run queue/enqueue_action ":producer='p'" ":collection='Outbox'" ":action='submit'" ":payload='{\"v\":1,\"source\":\"smtp\",\"from\":\"alice@example.org\",\"rcpts\":[\"bob@example.org\"]}'" ":object_hash='$m9'"
run owner/park_action ":id=1" ":error='refused'"
expect "collection: a collection holding a parked action is not deleted" \
    "$(fails owner/delete_collection ":collection='Outbox'" && echo refused)|$(sql "SELECT count(*) FROM queue;")" "refused|1"
pin="$(run owner/cancel_action ":id=1")"
run owner/release_pins ":hashes='[\"$pin\"]'"
run owner/delete_collection ":collection='Outbox'"
expect "collection: once its actions are cancelled it is" "$(sql "SELECT count(*) FROM collections WHERE id = 'Outbox';")" "0"

# --- A name is a label, not an address (§14) ---------------------------------

fresh
collection INBOX
expect "name: a collection with no name of its own is seeded with its id" \
    "$(sql "SELECT name FROM collections WHERE id = 'INBOX';")" "INBOX"
run owner/set_collection_name ":collection='INBOX'" ":account=NULL" ":name='Inbox'"
expect "name: the label moves" \
    "$(sql "SELECT name FROM collections WHERE id = 'INBOX';")" "Inbox"
expect "name: the id it is addressed by does not" \
    "$(sql "SELECT id, kind FROM collections;")" "INBOX|message/rfc822"
run owner/set_collection_name ":collection='Archive'" ":account=NULL" ":name='Archive'"
expect "name: naming an absent collection creates it with an undeclared kind" \
    "$(sql "SELECT kind FROM collections WHERE id = 'Archive';")" ""

# --- A role is what a source says a collection is for (§14) -----------------

fresh
collection INBOX work
collection Sent work
collection Old work
collection INBOX2 home
expect "role: a collection is declared with none" "$(sql "SELECT count(*) FROM collections WHERE role IS NOT NULL;")" "0"
run owner/set_collection_role ":collection='Sent'" ":role='sent'"
expect "role: the setter records it, and the reader lists it" \
    "$(run read/list_collections_by_account ":account='work'" | grep '^Sent|' | cut -d'|' -f10)" "sent"
cursor="$(run read/load_change_cursor | cut -d'|' -f1)"
run owner/set_collection_role ":collection='Old'" ":role='sent'"
expect "role: setting it on another collection moves it there" \
    "$(sql "SELECT id FROM collections WHERE role = 'sent';")" "Old"
expect "role: the move stamps both collections in the feed" \
    "$(run read/list_collections_changed_since ":since=$cursor" ":limit=10" | cut -d'|' -f1 | sort | tr '\n' ' ')" "Old Sent "
run owner/set_collection_role ":collection='INBOX'" ":role='inbox'"
run owner/set_collection_role ":collection='INBOX2'" ":role='inbox'"
expect "role: each account holds its own" \
    "$(sql "SELECT id FROM collections WHERE role = 'inbox' ORDER BY id;" | tr '\n' ' ')" "INBOX INBOX2 "
expect "role: a direct second holder is refused by the index" \
    "$(sql "DROP TRIGGER collections_role_moves; UPDATE collections SET role = 'inbox' WHERE id = 'Sent';" 2>&1 | grep -c UNIQUE)" "1"
fresh
collection INBOX
run owner/set_collection_role ":collection='INBOX'" ":role='snoozed'"
expect "role: the vocabulary is open, a role it does not list yet is recorded" \
    "$(sql "SELECT role FROM collections WHERE id = 'INBOX';")" "snoozed"
run owner/set_collection_kind ":collection='Cal'" ":account=NULL" ":kind='text/calendar'"
run owner/set_collection_role ":collection='Cal'" ":role='default'"
expect "role: a calendar is the default one" "$(sql "SELECT role FROM collections WHERE id = 'Cal';")" "default"
run owner/set_collection_role ":collection='Cal'" ":role=NULL"
expect "role: a source no longer saying it clears it" "$(sql "SELECT count(*) FROM collections WHERE id = 'Cal' AND role IS NOT NULL;")" "0"

# --- Closed vocabularies are held by the schema (§13) -----------------------

fresh
run owner/set_collection_kind ":collection='Lists'" ":account=NULL" ":kind='text/x-vlist'" >/dev/null 2>&1 || true
expect "kind: a fifth kind is refused, the collection never declared with it" \
    "$(sql "SELECT count(*) FROM collections WHERE id = 'Lists';")" "0"
run queue/ensure_collection ":collection='Bare'" ":account=NULL"
expect "kind: an undeclared collection is kindless, then takes a kind of the set" \
    "$(sql "SELECT kind FROM collections WHERE id = 'Bare';")|$(run owner/set_collection_kind ":collection='Bare'" ":account=NULL" ":kind='text/vcard'")$(sql "SELECT kind FROM collections WHERE id = 'Bare';")" "|text/vcard"
expect "kind: a fifth kind is refused over a declared one, which stays" \
    "$(fails owner/set_collection_kind ":collection='Bare'" ":account=NULL" ":kind='text/x-vlist'" && echo refused)|$(sql "SELECT kind FROM collections WHERE id = 'Bare';")" "refused|text/vcard"
expect "level: the ladder is 1 and 2, a 0 refused" \
    "$(fails owner/insert_item ":collection='Bare'" ":link_id='a'" ":seq=1" ":flags='[]'" ":object_hash=NULL" ":sort_key=''" ":level=0" ":deleted=0" ":conflicted=0" ":conflict_object=NULL" && echo refused)" "refused"
expect "vocabulary: conflict and support outside their sets are refused" \
    "$(sql "UPDATE collections SET conflict = 'newest' WHERE id = 'Bare';" 2>&1 | grep -c CHECK)$(fails owner/set_capability ":account=NULL" ":source='s'" ":collection=NULL" ":capability='mail.message.add'" ":support='some'" ":detail=NULL" && echo refused)" "1refused"

# --- Sources declare what they can do (§15.6) ---------------------------------

fresh
collection INBOX
run owner/upsert_checkpoint ":collection='INBOX'" ":source='graph'" ":checkpoint=NULL"
run owner/upsert_checkpoint ":collection='INBOX'" ":source='imap'" ":checkpoint=NULL"
expect "capability: a source with no row is listed undeclared" \
    "$(run read/load_capabilities ":collection='INBOX'" | tr '\n' ' ')" "graph||| imap||| "
run owner/delete_capabilities ":source='graph'"
run owner/set_capability ":account=NULL" ":source='graph'" ":collection=NULL" ":capability='mail.message.remove'" ":support='full'" ":detail=NULL"
run owner/set_capability ":account=NULL" ":source='graph'" ":collection=NULL" ":capability='mail.message.move'" ":support='none'" ":detail='pull-only'"
expect "capability: a declared source lists its rows, an undeclared one stays undeclared" \
    "$(run read/load_capabilities ":collection='INBOX'" | tr '\n' ' ')" \
    "graph|mail.message.move|none|pull-only graph|mail.message.remove|full| imap||| "
run owner/delete_capabilities ":source='graph'"
run owner/set_capability ":account=NULL" ":source='graph'" ":collection=NULL" ":capability='mail.message.remove'" ":support='full'" ":detail=NULL"
expect "capability: a declaration replaces the set, a lost capability does not linger" \
    "$(sql "SELECT capability FROM capabilities WHERE source = 'graph';")" "mail.message.remove"
if fails owner/set_capability ":account=NULL" ":source='graph'" ":collection=NULL" ":capability='mail.message.copy'" ":support='maybe'" ":detail=NULL"; then :; else
    expect "capability: support is one of three words" "accepted" "refused"
fi
item INBOX a 1
sql "INSERT INTO bindings(item, collection, source, handle) VALUES((SELECT id FROM items WHERE collection = 'INBOX' AND link_id = 'a'), 'INBOX', 'graph', '1');"
expect "capability: an item answers for the sources binding it alone" \
    "$(run read/load_item_capabilities ":collection='INBOX'" ":seq=1" | tr '\n' ' ')" "graph|mail.message.remove|full| "
run owner/set_capability ":account=NULL" ":source='graph'" ":collection=NULL" ":capability='mail.submit'" ":support='full'" ":detail=NULL"
run owner/set_capability ":account=NULL" ":source='imap'" ":collection=NULL" ":capability='mail.submit'" ":support='partial'" ":detail='no Bcc'"
expect "capability: two candidates make an intent ambiguous" \
    "$(run read/list_capability_sources ":account=NULL" ":collection=NULL" ":capability='mail.submit'" | tr '\n' ' ')" "graph|full| imap|partial|no Bcc "
run owner/set_capability ":account=NULL" ":source='graph'" ":collection=NULL" ":capability='mail.submit'" ":support='none'" ":detail=NULL"
expect "capability: a none row is no candidate" \
    "$(run read/list_capability_sources ":account=NULL" ":collection=NULL" ":capability='mail.submit'" | cut -d'|' -f1)" "imap"
collection work/INBOX "'work'"
run owner/upsert_checkpoint ":collection='work/INBOX'" ":source='work-smtp'" ":checkpoint=NULL"
run owner/set_capability ":account='work'" ":source='work-smtp'" ":collection=NULL" ":capability='mail.submit'" ":support='full'" ":detail=NULL"
expect "capability: candidates are the account's own" \
    "$(run read/list_capability_sources ":account='work'" ":collection=NULL" ":capability='mail.submit'" | cut -d'|' -f1)" "work-smtp"
run owner/set_capability ":account='work'" ":source='work-graph'" ":collection=NULL" ":capability='mail.submit'" ":support='full'" ":detail=NULL"
expect "capability: a declared source is a candidate before it syncs anything" \
    "$(run read/list_capability_sources ":account='work'" ":collection=NULL" ":capability='mail.submit'" | cut -d'|' -f1 | tr '\n' ' ')" "work-graph work-smtp "
run owner/set_performer ":account=NULL" ":capability='mail.submit'" ":source='graph'"
run owner/set_performer ":account=NULL" ":capability='mail.submit'" ":source='imap'"
run owner/set_performer ":account='work'" ":capability='mail.submit'" ":source='work-smtp'"
expect "performer: one choice per account and capability, the last one kept" \
    "$(run read/load_performer ":account=NULL" ":capability='mail.submit'")" "imap"
expect "performer: accounts choose apart" "$(sql "SELECT count(*) FROM performers;")" "2"
run owner/delete_performer ":account=NULL" ":capability='mail.submit'"
expect "performer: a withdrawn choice leaves the other account's" \
    "$(run read/load_performer ":account=NULL" ":capability='mail.submit'")$(run read/load_performer ":account='work'" ":capability='mail.submit'")" "work-smtp"


# --- A calendar refusing tasks says so, before its first sync (§15.6) -------

fresh
collection Events
collection Tasks
# NOTE: a source registers each calendar it lists with no checkpoint, so its
# declaration is read before the first item sync binds anything there.
run owner/upsert_checkpoint ":collection='Events'" ":source='caldav'" ":checkpoint=NULL"
run owner/upsert_checkpoint ":collection='Tasks'" ":source='caldav'" ":checkpoint=NULL"
run owner/set_capability ":account=NULL" ":source='caldav'" ":collection='Events'" ":capability='calendar.component.vtodo'" ":support='none'" ":detail='VEVENT only'"
expect "calendar.component.vtodo: a listed calendar never synced refuses tasks by its row" \
    "$(run read/load_capabilities ":collection='Events'" | grep calendar.component.vtodo)" "caldav|calendar.component.vtodo|none|VEVENT only"
expect "calendar.component.vtodo: a calendar with no row states nothing by it" \
    "$(run read/load_capabilities ":collection='Tasks'" | grep -c calendar.component.vtodo)" "0"
run owner/set_capability ":account=NULL" ":source='caldav'" ":collection=NULL" ":capability='calendar.component.vtodo'" ":support='none'" ":detail='events only'"
run owner/set_capability ":account=NULL" ":source='caldav'" ":collection='Tasks'" ":capability='calendar.component.vtodo'" ":support='full'" ":detail=NULL"
expect "calendar.component.vtodo: a calendar stating full wins over a source-wide none" \
    "$(run read/load_capabilities ":collection='Tasks'" | grep calendar.component.vtodo)" "caldav|calendar.component.vtodo|full|"
# --- A collection overrides its source's declaration there (§15.6) -----------

fresh
collection Personal
collection Holidays
run owner/upsert_checkpoint ":collection='Personal'" ":source='google'" ":checkpoint=NULL"
run owner/upsert_checkpoint ":collection='Holidays'" ":source='google'" ":checkpoint=NULL"
run owner/set_capability ":account=NULL" ":source='google'" ":collection=NULL" ":capability='calendar.item.add'" ":support='full'" ":detail=NULL"
run owner/set_capability ":account=NULL" ":source='google'" ":collection=NULL" ":capability='calendar.reply'" ":support='full'" ":detail=NULL"
run owner/set_capability ":account=NULL" ":source='google'" ":collection='Holidays'" ":capability='calendar.item.add'" ":support='none'" ":detail='read-only calendar'"
expect "override: the source-wide row holds where nothing overrides it" \
    "$(run read/load_capabilities ":collection='Personal'" | grep item.add)" "google|calendar.item.add|full|"
expect "override: a collection's row wins there, the rest still holds" \
    "$(run read/load_capabilities ":collection='Holidays'" | tr '\n' ' ')" \
    "google|calendar.item.add|none|read-only calendar google|calendar.reply|full| "
run owner/set_capability ":account=NULL" ":source='google'" ":collection='Holidays'" ":capability='calendar.reply'" ":support='none'" ":detail=NULL"
expect "override: an intent anchored where the source refuses it has no candidate there" \
    "$(run read/list_capability_sources ":account=NULL" ":collection='Holidays'" ":capability='calendar.reply'" | cut -d'|' -f1)$(run read/list_capability_sources ":account=NULL" ":collection='Personal'" ":capability='calendar.reply'" | cut -d'|' -f1)" "google"

run owner/rename_collection ":collection='Holidays'" ":new_id='Holidays-FR'"
expect "override: a rename carries it" \
    "$(sql "SELECT collection FROM capabilities WHERE collection IS NOT NULL GROUP BY collection;")" "Holidays-FR"
run owner/delete_capabilities ":source='google'"
expect "override: a declaration's reset takes the overrides with it" "$(sql "SELECT count(*) FROM capabilities;")" "0"

# --- Implementations: a native one where it holds, iMIP anywhere (§15.6) ------

fresh
collection Work
collection Home
run owner/set_capability ":account=NULL" ":source='graph'" ":collection=NULL" ":capability='calendar.reply'" ":support='none'" ":detail='only the calendars it holds'"
run owner/set_capability ":account=NULL" ":source='graph'" ":collection='Home'" ":capability='calendar.reply'" ":support='full'" ":detail=NULL"
run owner/set_capability ":account=NULL" ":source='smtp'" ":collection=NULL" ":capability='calendar.reply'" ":support='partial'" ":detail='by iMIP'"
expect "implementations: a collection row makes a candidate there alone" \
    "$(run read/list_capability_sources ":account=NULL" ":collection='Home'" ":capability='calendar.reply'" | cut -d'|' -f1 | tr '\n' ' ')" "graph smtp "
expect "implementations: a source-wide one is a candidate everywhere" \
    "$(run read/list_capability_sources ":account=NULL" ":collection='Work'" ":capability='calendar.reply'" | cut -d'|' -f1)" "smtp"
expect "implementations: the account lists every source able somewhere" \
    "$(run read/list_capability_sources ":account=NULL" ":collection=NULL" ":capability='calendar.reply'" | tr '\n' ' ')" "graph|full| smtp|partial|by iMIP "

# --- A producer follows its row to the item it created (§15.2, §15.4) ---------

fresh
collection INBOX
object "$h1"
run queue/pin_object ":hash='$h1'"
run queue/enqueue_action ":producer='p'" ":collection='INBOX'" ":action='add'" ":payload='{\"v\":1,\"link_id\":\"mid:a\",\"flags\":[],\"object\":\"$h1\"}'" ":object_hash='$h1'"
run queue/enqueue_action ":producer='p'" ":collection='INBOX'" ":action='remove'" ":payload='{\"v\":1,\"seq\":9}'" ":object_hash=NULL"
expect "receipt: a pending row reads as itself, unparked" \
    "$(run read/load_action ":id=1" | cut -d'|' -f1,4,5,9)" "1|INBOX|add|"
run owner/park_action ":id=2" ":error='unknown seq: 9'"
expect "receipt: a parked row reads with its error" \
    "$(run read/load_action ":id=2" | cut -d'|' -f9)" "unknown seq: 9"
run owner/claim_action ":id=1" >/dev/null
item INBOX mid:a 7
run owner/record_receipt ":id=1" ":collection='INBOX'" ":seq=$(run read/seq_by_link ":collection='INBOX'" ":link_id='mid:a'")"
expect "receipt: an applied add is gone from the queue and names its item" \
    "$(run read/load_action ":id=1")$(run read/load_receipt ":id=1" | cut -d'|' -f2,3)" "INBOX|7"
expect "receipt: a cancelled row leaves none" \
    "$(run owner/cancel_action ":id=2" >/dev/null; run read/load_action ":id=2")$(run read/load_receipt ":id=2")" ""
run owner/rename_collection ":collection='INBOX'" ":new_id='Inbox'"
expect "receipt: a rename carries it" "$(run read/load_receipt ":id=1" | cut -d'|' -f2)" "Inbox"
run owner/prune_receipts ":before='2000-01-01T00:00:00.000Z'"
expect "receipt: pruning keeps what is younger" "$(sql "SELECT count(*) FROM receipts;")" "1"
run owner/prune_receipts ":before='9999-01-01T00:00:00.000Z'"
expect "receipt: pruning drops what is older" "$(run read/load_receipt ":id=1")" ""
run queue/pin_object ":hash='$h1'"
run queue/enqueue_action ":producer='p'" ":collection='Inbox'" ":action='add'" ":payload='{\"v\":1,\"flags\":[],\"object\":\"$h1\"}'" ":object_hash='$h1'"
expect "receipt: a queue id is never reused, so an old receipt names no new row" \
    "$(run read/load_action ":id=3" | cut -d'|' -f1)" "3"

# --- A performed intent leaves a receipt, a withdrawn one none (§15.5) ------

fresh
collection INBOX
collection Sent
object "$m1"
run queue/enqueue_action ":producer='p'" ":collection='INBOX'" ":action='collection-create'" ":payload='{\"v\":1,\"source\":\"imap\",\"name\":\"Projects\"}'" ":object_hash=NULL"
run queue/enqueue_action ":producer='p'" ":collection='INBOX'" ":action='collection-create'" ":payload='{\"v\":1,\"source\":\"imap\",\"name\":\"Other\"}'" ":object_hash=NULL"
run queue/pin_object ":hash='$m1'"
run queue/enqueue_action ":producer='p'" ":collection='Sent'" ":action='submit'" ":payload='{\"v\":1,\"source\":\"smtp\",\"from\":\"alice@example.org\",\"rcpts\":[\"bob@example.org\"],\"copy\":\"Sent\"}'" ":object_hash='$m1'"
run owner/cancel_action ":id=1" >/dev/null
run owner/record_receipt ":id=1" ":collection='INBOX'" ":seq=NULL"
run owner/cancel_action ":id=2" >/dev/null
expect "acknowledge: a performed intent reads as applied, naming no item" \
    "$(run read/load_action ":id=1")$(run read/load_receipt ":id=1" | cut -d'|' -f2,3)" "INBOX|"
expect "acknowledge: a withdrawn intent leaves none" \
    "$(run read/load_action ":id=2")$(run read/load_receipt ":id=2")" ""
run queue/pin_object ":hash='$m1'"
run queue/enqueue_action ":producer='owner'" ":collection='Sent'" ":action='add'" ":payload='{\"v\":1,\"flags\":[\"\\\\Seen\"],\"object\":\"$m1\"}'" ":object_hash='$m1'"
pin="$(run owner/cancel_action ":id=3")"
run owner/record_receipt ":id=3" ":collection='Sent'" ":seq=NULL"
run owner/release_pins ":hashes='[\"$pin\"]'"
expect "acknowledge: a replaced intent reads as applied, its change a row of its own" \
    "$(run read/load_receipt ":id=3" | cut -d'|' -f2)$(run read/load_action ":id=4" | cut -d'|' -f5)" "Sentadd"


# --- Nothing reaches the store unnamed (§10, SYNC.md §4) ---------------------

fresh
expect "probes: the table is gone, every listed member being named" \
    "$(sql "SELECT count(*) FROM sqlite_schema WHERE name = 'probes';")" "0"

# --- One identity keeps one seq within its kind (§9, §9.1) -------------------

fresh
collection INBOX
collection Archive
for spec in Cal:text/calendar Files:application/octet-stream Folder:application/octet-stream; do
    run owner/set_collection_kind ":collection='${spec%%:*}'" ":account=NULL" ":kind='${spec#*:}'"
done
item Cal 'x@example.org' 1
item INBOX 'm@example.org' 2
item Files 'part:m@example.org#2' 3
run owner/retain_item ":collection='INBOX'" ":link_id='m@example.org'" ":source='s'"
expect "seq: a Message-ID spelling an event's UID is another item, drawing its own seq" \
    "$(run owner/seq_for_link_any ":collection='INBOX'" ":link_id='x@example.org'")" ""
expect "seq: a message filed twice shares one, retained or not, and so does a part's file in two folders" \
    "$(run owner/seq_for_link_any ":collection='Archive'" ":link_id='m@example.org'")|$(run owner/seq_for_link_any ":collection='Folder'" ":link_id='part:m@example.org#2'")|$(run owner/seq_for_link_any ":collection='Cal'" ":link_id='part:m@example.org#2'")" \
    "2|3|"
steps="$(plan owner/seq_for_link_any ":collection='INBOX'" ":link_id='x@example.org'")"
expect "seq: seq_for_link_any seeks the link id on items_by_link and each collection by its key, scanning nothing" \
    "$(grep -c 'SEARCH held USING INDEX items_by_link (link_id=?)' <<<"$steps" || true)$(grep -c 'SCAN' <<<"$steps" || true)" "10"

# --- A key is held by any row; a minted key mints again (§9) ----------------

fresh
collection INBOX
item INBOX 'k@example.org' 1
item INBOX 'dup:k@example.org#7' 2
run owner/retain_item ":collection='INBOX'" ":link_id='dup:k@example.org#7'" ":source='s'"
sql "UPDATE items SET deleted = 1 WHERE link_id = 'k@example.org';"
expect "held: seq_by_link answers a tombstoned and a retained row alike, and nothing for a free key" \
    "$(run read/seq_by_link ":collection='INBOX'" ":link_id='k@example.org'")|$(run read/seq_by_link ":collection='INBOX'" ":link_id='dup:k@example.org#7'")|$(run read/seq_by_link ":collection='INBOX'" ":link_id='dup:dup:k@example.org#7#7'")" \
    "1|2|"
expect "held: live_item_for_link answers neither, being the live test of the Add column, never the held one minting reads" \
    "$(run owner/live_item_for_link ":collection='INBOX'" ":link_id='k@example.org'")|$(run owner/live_item_for_link ":collection='INBOX'" ":link_id='dup:k@example.org#7'")" "|"

# --- A round is stamped page by page and closed once (SYNC.md §5) -----------

# mail <collection> <link_id> <seq> <handle> <date|NULL> [flags] [base_flags]:
# a bound item with its summary, as a page's write leaves it.
mail() {
    run owner/insert_item ":collection='$1'" ":link_id='$2'" ":seq=$3" ":flags='${6:-[]}'" \
        ":object_hash=NULL" ":sort_key=''" ":level=1" ":deleted=0" ":conflicted=0" ":conflict_object=NULL"
    run owner/insert_binding ":collection='$1'" ":link_id='$2'" ":source='imap'" ":handle='$4'" \
        ":base_flags='${7:-[]}'" ":base_object=NULL" ":base_revision=NULL" ":base_present=1" \
        ":conflicted=0" ":conflict_revision=NULL" ":conflict_object=NULL" ":shared_object=NULL"
    run owner/upsert_mail_summary ":collection='$1'" ":link_id='$2'" ":message_id='$2'" \
        ":in_reply_to='[]'" ":subject='s $2'" ":sender='alice@example.org'" ":sender_name='Alice'" \
        ":date=$5" ":size=1" ":attachment=0"
}

fresh
collection INBOX
mail INBOX recent 1 30 "'2026-10-06T08:00:00Z'"
mail INBOX old 2 10 "'2026-08-01T10:00:00Z'"
mail INBOX nodate 3 20 NULL
mail INBOX gone 4 25 "'2026-10-01T00:00:00Z'"
sql "INSERT INTO items(collection, link_id, seq, flags_known, level) VALUES('INBOX', 'draft', 5, 1, 2);
     INSERT INTO bindings(item, collection, source, handle) VALUES((SELECT id FROM items WHERE collection = 'INBOX' AND link_id = 'draft'), 'INBOX', 'imap', char(1) || 'draft');
     INSERT INTO mail_summary(item, subject, date) VALUES((SELECT id FROM items WHERE collection = 'INBOX' AND link_id = 'draft'), '', '2026-10-06T09:00:00Z');"
run owner/upsert_checkpoint ":collection='INBOX'" ":source='imap'" ":checkpoint=x'6330'"
run owner/open_round ":collection='INBOX'" ":source='imap'" ":since='2026-09-01T00:00:00Z'" ":until=NULL" ":band=0"
expect "round: the first round draws id 1, the checkpoint stays" \
    "$(run owner/load_round ":collection='INBOX'" ":source='imap'" | cut -d'|' -f1,3)$(run owner/load_checkpoint ":collection='INBOX'" ":source='imap'" | cut -d'|' -f1)" \
    "1|2026-09-01T00:00:00Zc0"
run owner/stamp_bindings ":collection='INBOX'" ":source='imap'" ":handles='[\"30\"]'"
run owner/set_round_cursor ":collection='INBOX'" ":source='imap'" ":cursor=x'7031'" ":checkpoint=x'6331'"
run owner/set_round_cursor ":collection='INBOX'" ":source='imap'" ":cursor=x'7032'" ":checkpoint=NULL"
expect "round: a page lands its cursor, a later page keeps the checkpoint it carries none of" \
    "$(run owner/load_round ":collection='INBOX'" ":source='imap'" | cut -d'|' -f5,6)" "p2|c1"
run owner/set_round_cursor ":collection='INBOX'" ":source='imap'" ":cursor=NULL" ":checkpoint=x'6335'"
expect "round: a delta head lands its checkpoint and keeps the cursor a page landed" \
    "$(run owner/load_round ":collection='INBOX'" ":source='imap'" | cut -d'|' -f5,6)" "p2|c5"
expect "round: the last page infers deletes in scope only, the undated always in it, never a pending create" \
    "$(run owner/list_unstamped_bindings ":collection='INBOX'" ":source='imap'" ":narrowed=0" ":enumerated=0" | tr '\n' ' ')" "20|nodate 25|gone "
run owner/open_round ":collection='INBOX'" ":source='imap'" ":since='2026-09-01T00:00:00Z'" ":until=NULL" ":band=0"
expect "round: a restart draws a new id, voiding the cursor, the checkpoint and the old stamps" \
    "$(run owner/load_round ":collection='INBOX'" ":source='imap'" | cut -d'|' -f1,5,6)|$(run owner/list_unstamped_bindings ":collection='INBOX'" ":source='imap'" ":narrowed=0" ":enumerated=0" | cut -d'|' -f1 | tr '\n' ' ')" \
    "2|||20 25 30 "
run owner/stamp_bindings ":collection='INBOX'" ":source='imap'" ":handles='[\"20\",\"30\"]'"
run owner/set_round_cursor ":collection='INBOX'" ":source='imap'" ":cursor=NULL" ":checkpoint=x'6332'"
cursor="$(run read/load_change_cursor | cut -d'|' -f1)"
run owner/close_round ":collection='INBOX'" ":source='imap'" ":checkpoint=NULL" ":since='2026-09-01T00:00:00Z'" ":until=NULL"
expect "round: closing lands the round's checkpoint and its coverage, and clears the round" \
    "$(run owner/load_checkpoint ":collection='INBOX'" ":source='imap'" | cut -d'|' -f1,2)|$(run owner/load_round ":collection='INBOX'" ":source='imap'" | cut -d'|' -f1-6)" \
    "c2|2026-09-01T00:00:00Z|2|||||"
expect "round: the coverage is stamped by SQLite" \
    "$(sql "SELECT covered_at LIKE '____-__-__T__:__:__.___Z' FROM sources;")" "1"
expect "coverage: a closing moves the collection in the feed" \
    "$(run read/list_collections_changed_since ":since=$cursor" ":limit=10" | cut -d'|' -f1)" "INBOX"
expect "coverage: a reader lists it with the collection" \
    "$(run read/list_collections | cut -d'|' -f1,11,12)" "INBOX|2026-09-01T00:00:00Z|"
run owner/upsert_checkpoint ":collection='INBOX'" ":source='graph'" ":checkpoint=NULL"
expect "coverage: a collection with a source never complete has none" \
    "$(run read/list_collections | cut -d'|' -f11,13)" "|"
expect "coverage: per source, the round under way included" \
    "$(run read/list_coverage ":collection='INBOX'" | cut -d'|' -f1,2,5 | tr '\n' ' ')" "graph|| imap|2026-09-01T00:00:00Z| "
run owner/set_coverage ":collection='INBOX'" ":source='imap'" ":since='2026-10-01T00:00:00Z'" ":until=NULL"
run owner/set_coverage ":collection='INBOX'" ":source='graph'" ":since='2026-10-01T00:00:00Z'" ":until=NULL"
expect "coverage: a narrower scope restates it, a source never complete gains none" \
    "$(run read/list_coverage ":collection='INBOX'" | cut -d'|' -f1,2 | tr '\n' ' ')" "graph| imap|2026-10-01T00:00:00Z "
expect "coverage: a bound without a closing is refused by the schema" \
    "$(sql "UPDATE sources SET covered_since = 'x' WHERE source = 'graph';" 2>&1 | grep -c CHECK)" "1"
expect "round: no round, no cursor, by the schema" \
    "$(sql "UPDATE sources SET round_cursor = x'78' WHERE source = 'graph';" 2>&1 | grep -c CHECK)" "1"
expect "round: no round, no band, by the schema" \
    "$(sql "UPDATE sources SET round_band = 1 WHERE source = 'graph';" 2>&1 | grep -c CHECK)" "1"

# --- A band round infers no delete of an undated member (SYNC.md §5) --------

fresh
collection INBOX
mail INBOX recent 1 30 "'2026-10-06T08:00:00Z'"
mail INBOX old 2 10 "'2026-08-01T10:00:00Z'"
mail INBOX older 3 5 "'2026-06-01T10:00:00Z'"
mail INBOX nodate 4 20 NULL
run owner/open_round ":collection='INBOX'" ":source='imap'" ":since='2026-07-01T00:00:00Z'" ":until='2026-09-01T00:00:00Z'" ":band=1"
expect "band: the round records that it lists the band alone" \
    "$(run owner/load_round ":collection='INBOX'" ":source='imap'" | cut -d'|' -f3,4,7)" \
    "2026-07-01T00:00:00Z|2026-09-01T00:00:00Z|1"
expect "band: the last page infers deletes inside the band only, never of an undated member" \
    "$(run owner/list_unstamped_bindings ":collection='INBOX'" ":source='imap'" ":narrowed=0" ":enumerated=0" | tr '\n' ' ')" "10|old "
run owner/close_round ":collection='INBOX'" ":source='imap'" ":checkpoint=NULL" ":since='2026-07-01T00:00:00Z'" ":until=NULL"
expect "band: closing clears the band with the round" \
    "$(run owner/load_round ":collection='INBOX'" ":source='imap'" | cut -d'|' -f2,7)" "|0"
run owner/open_round ":collection='INBOX'" ":source='imap'" ":since='2026-07-01T00:00:00Z'" ":until=NULL" ":band=0"
expect "band: a round over the whole scope still finds the undated member absent" \
    "$(run owner/list_unstamped_bindings ":collection='INBOX'" ":source='imap'" ":narrowed=0" ":enumerated=0" | tr '\n' ' ')" "10|old 20|nodate 30|recent "

# --- A narrowed listing proves only what its filter could list (SYNC.md §4, §5)

fresh
collection INBOX
mail INBOX recent 1 30 "'2026-10-06T08:00:00Z'"
mail INBOX nodate 2 20 NULL
mail INBOX future 3 40 "'2035-01-01T00:00:00Z'"
run owner/open_round ":collection='INBOX'" ":source='imap'" ":since='2026-09-01T00:00:00Z'" ":until=NULL" ":band=0"
expect "narrowed: a listing no filter narrowed finds every unlisted member of its scope absent" \
    "$(run owner/list_unstamped_bindings ":collection='INBOX'" ":source='imap'" ":narrowed=0" ":enumerated=0" | tr '\n' ' ')" "20|nodate 30|recent 40|future "
expect "narrowed: a narrowed one, only a member dated before the round opened, never the undated nor the future-dated" \
    "$(run owner/list_unstamped_bindings ":collection='INBOX'" ":source='imap'" ":narrowed=1" ":enumerated=0" | tr '\n' ' ')" "30|recent "
expect "narrowed: an unfiltered enumeration of handles finds absent the undated or future-dated member it lacks, alone" \
    "$(run owner/list_unstamped_bindings ":collection='INBOX'" ":source='imap'" ":narrowed=1" ":enumerated=1" ":handles='[\"20\"]'" | tr '\n' ' ')" "30|recent 40|future "

# --- Collecting below a date is manual and pushes nothing (§11.3) -----------

fresh
collection INBOX
collection Archive
object "$h1"
mail INBOX old 1 10 "'2026-08-01T10:00:00Z'"
sql "UPDATE items SET object_hash = '$h1' WHERE link_id = 'old'; UPDATE bindings SET base_object = '$h1' WHERE item IN (SELECT id FROM items WHERE link_id = 'old');"
mail INBOX dirty 2 11 "'2026-08-01T10:00:00Z'" '["\\Flagged"]' '[]'
mail INBOX recent 3 12 "'2026-10-06T08:00:00Z'"
mail INBOX nodate 4 13 NULL
mail Archive old 1 10 "'2026-08-01T10:00:00Z'"
sql "INSERT INTO items(collection, link_id, seq, flags_known, level) VALUES('INBOX', 'created', 5, 1, 2);
     INSERT INTO bindings(item, collection, source, handle) VALUES((SELECT id FROM items WHERE collection = 'INBOX' AND link_id = 'created'), 'INBOX', 'imap', char(1) || 'created');
     INSERT INTO mail_summary(item, subject, date) VALUES((SELECT id FROM items WHERE collection = 'INBOX' AND link_id = 'created'), '', '2026-08-01T10:00:00Z');"
run owner/recompute_refcounts
purges="$(sql "SELECT purges FROM store_meta;")"
expect "collect: only what owes nothing, below the date, in the collection" \
    "$(run owner/collect_before ":collection='INBOX'" ":before='2026-09-01T00:00:00Z'")" "1"
run owner/recompute_refcounts
expect "collect: an unpushed flag, a pending create, the undated and the newer stay" \
    "$(sql "SELECT link_id FROM items WHERE collection = 'INBOX' ORDER BY link_id;" | tr '\n' ' ')" "created dirty nodate recent "
expect "collect: bindings, summary and addresses go with the item" \
    "$(sql "SELECT (SELECT count(*) FROM bindings WHERE collection = 'INBOX' AND item IN (SELECT id FROM items WHERE link_id = 'old')) + (SELECT count(*) FROM mail_summary WHERE item IN (SELECT id FROM items WHERE collection = 'INBOX' AND link_id = 'old'));")" "0"
expect "collect: the body is released to the collector, the holder elsewhere untouched" \
    "$(sql "SELECT refcount FROM objects WHERE hash = '$h1';")$(sql "SELECT count(*) FROM items WHERE collection = 'Archive';")" "01"
expect "collect: no tombstone, no queued push, and the feed counts a purge" \
    "$(sql "SELECT count(*) FROM items WHERE deleted = 1;")$(sql "SELECT count(*) FROM queue;")$(sql "SELECT purges FROM store_meta;")" "00$((purges + 1))"
run owner/set_collection_kind ":collection='Cards'" ":account=NULL" ":kind='text/vcard'"
item Cards card 20
mail INBOX kept 6 14 "'2026-08-01T10:00:00Z'"
mail INBOX told 7 15 "'2026-08-01T10:00:00Z'"
mail INBOX target 8 16 "'2026-08-01T10:00:00Z'"
for pair in "kept|message/rfc822|card|text/vcard|related|user" "card|text/vcard|target|message/rfc822|related|user" \
            "told|message/rfc822|card|text/vcard|sender|auto"; do
    IFS='|' read -r fl fk tl tk role origin <<<"$pair"
    run owner/add_reference ":from_kind='$fk'" ":from_link_id='$fl'" ":to_kind='$tk'" ":to_link_id='$tl'" ":role='$role'" ":origin='$origin'" >/dev/null
done
expect "collect: a mail a person's reference names, from either end, stays; a rule's reference does not hold one" \
    "$(run owner/collect_before ":collection='INBOX'" ":before='2026-09-01T00:00:00Z'")|$(sql "SELECT count(*) FROM item_reference WHERE origin = 'user';")" "7|2"
# A mail no source binds is the store's alone (a copy kept on the device):
# no relisting restores it, so it owes its own keeping (§11.3).
sql "INSERT INTO items(collection, link_id, seq, flags_known, object_hash, level) VALUES('INBOX', 'local', 9, 1, '$h1', 2);
     INSERT INTO mail_summary(item, subject, date) VALUES((SELECT id FROM items WHERE collection = 'INBOX' AND link_id = 'local'), 'kept here', '2026-08-01T10:00:00Z');"
expect "collect: a mail no source binds stays, no relisting restoring it" \
    "$(run owner/collect_before ":collection='INBOX'" ":before='2026-09-01T00:00:00Z'")|$(sql "SELECT count(*) FROM items WHERE link_id = 'local';")" "|1"

# --- Releasing bodies below a date keeps the headers (§11.4) ----------------

fresh
collection INBOX
collection Archive
collection Both
run owner/set_collection_kind ":collection='Cards'" ":account=NULL" ":kind='text/vcard'"
for hash in "$h1" "$h2" "$h3" "$h4" "$h5" "$h6" "$h7" "$h8" "$h9" "$hc"; do object "$hash"; done
run owner/upsert_checkpoint ":collection='INBOX'" ":source='imap'" ":checkpoint=NULL"
mail INBOX old 1 10 "'2026-08-01T10:00:00Z'"
mail INBOX dirty 2 11 "'2026-08-01T10:00:00Z'" '["\\Flagged"]' '[]'
mail INBOX nodate 3 12 NULL
mail INBOX recent 4 13 "'2026-10-06T08:00:00Z'"
mail INBOX conflicted 5 14 "'2026-08-01T10:00:00Z'"
mail INBOX diverged 6 15 "'2026-08-01T10:00:00Z'"
mail INBOX edited 7 16 "'2026-08-01T10:00:00Z'"
mail INBOX witness 8 17 "'2026-08-01T10:00:00Z'"
mail INBOX gone 11 18 "'2026-08-01T10:00:00Z'"
mail Archive old 1 10 "'2026-08-01T10:00:00Z'"
mail Both full 9 20 "'2026-08-01T10:00:00Z'"
mail Both half 10 21 "'2026-08-01T10:00:00Z'"
sql "UPDATE items SET sort_key = coalesce((SELECT date FROM mail_summary s WHERE s.item = items.id), ''), level = 2;
     UPDATE items SET object_hash = CASE link_id WHEN 'old' THEN '$h1' WHEN 'dirty' THEN '$h2' WHEN 'nodate' THEN '$h3' WHEN 'recent' THEN '$h4'
         WHEN 'conflicted' THEN '$h5' WHEN 'diverged' THEN '$h6' WHEN 'edited' THEN '$h7' WHEN 'witness' THEN '$h8' ELSE '$h9' END;
     UPDATE bindings SET base_object = (SELECT object_hash FROM items i WHERE i.id = bindings.item),
         shared_object = (SELECT object_hash FROM items i WHERE i.id = bindings.item);
     UPDATE items SET conflicted = 1, conflict_object = '$hc' WHERE link_id = 'conflicted';
     UPDATE bindings SET conflicted = 1 WHERE item IN (SELECT id FROM items WHERE link_id = 'diverged');
     UPDATE bindings SET base_object = '$h1' WHERE item IN (SELECT id FROM items WHERE link_id = 'edited');
     UPDATE bindings SET base_present = 0, base_flags_known = 0 WHERE item IN (SELECT id FROM items WHERE link_id = 'witness');
     UPDATE items SET deleted = 1 WHERE link_id = 'gone';
     INSERT INTO items(collection, link_id, seq, flags_known, object_hash, sort_key, level) VALUES
         ('INBOX', 'created', 20, 1, '$h9', '2026-08-01T10:00:00Z', 2),
         ('INBOX', 'lone', 21, 1, '$h9', '2026-08-01T10:00:00Z', 2),
         ('Cards', 'card', 22, 0, '$h9', '2026-08-01', 2);
     INSERT INTO bindings(item, collection, source, handle) VALUES((SELECT id FROM items WHERE collection = 'INBOX' AND link_id = 'created'), 'INBOX', 'imap', char(1) || 'created');
     INSERT INTO bindings(item, collection, source, handle, base_present, base_object) VALUES((SELECT id FROM items WHERE collection = 'Cards' AND link_id = 'card'), 'Cards', 'dav', 'c', 1, '$h9');
     INSERT INTO bindings(item, collection, source, handle, base_flags_known, base_object, base_present)
         VALUES((SELECT id FROM items WHERE collection = 'Both' AND link_id = 'full'), 'Both', 'graph', 'g20', 1, '$h9', 1);
     INSERT INTO sources(collection, source) VALUES('Both', 'imap'), ('Both', 'graph');"
run owner/recompute_refcounts
cursor="$(run read/load_change_cursor | cut -d'|' -f1)"
set=":collections='[\"INBOX\",\"Both\",\"Cards\"]'"
run owner/release_bases_before "$set" ":until='2026-09-01T00:00:00Z'"
expect "release: below the date, what needs no body, the undated included, two sources' bases alike" \
    "$(run owner/release_before "$set" ":until='2026-09-01T00:00:00Z'" | sort -n | tr '\n' ' ')" "1 2 3 8 9 "
run owner/recompute_refcounts
expect "release: a conflict, a diverged binding, a local edit, a pending create, no binding, an unbound source, another kind, a tombstone, the newer and an unnamed collection keep theirs" \
    "$(sql "SELECT collection || ':' || link_id FROM items WHERE object_hash IS NOT NULL ORDER BY collection, link_id;" | tr '\n' ' ')" \
    "Archive:old Both:half Cards:card INBOX:conflicted INBOX:created INBOX:diverged INBOX:edited INBOX:gone INBOX:lone INBOX:recent "
expect "release: a tombstone, a newer item, a conflicted one and another kind keep their bases" \
    "$(sql "SELECT count(*) FROM bindings WHERE item IN (SELECT id FROM items WHERE link_id IN ('gone', 'recent', 'conflicted', 'card')) AND base_object IS NOT NULL;")|$(sql "SELECT object_hash FROM items WHERE link_id = 'gone';")" "4|$h9"
expect "release: back to Meta, flags, summary and addresses kept" \
    "$(sql "SELECT level, flags_known FROM items WHERE collection = 'INBOX' AND link_id = 'dirty';")|$(flags INBOX dirty)|$(sql "SELECT count(*) FROM mail_summary WHERE item IN (SELECT id FROM items WHERE collection = 'INBOX') AND item IN (SELECT id FROM items WHERE link_id IN ('old', 'dirty', 'nodate', 'witness'));")" \
    '1|1|\Flagged|4'
expect "release: a shared body naming the released body lets go of it, another stays" \
    "$(sql "SELECT count(*) FROM bindings WHERE item IN (SELECT id FROM items WHERE link_id IN ('old', 'dirty', 'nodate', 'witness')) AND collection = 'INBOX' AND shared_object IS NULL;")|$(sql "SELECT shared_object FROM bindings WHERE item IN (SELECT id FROM items WHERE link_id = 'edited');")" "4|$h7"
expect "release: the bases let go of the body, every binding still based, its flags kept" \
    "$(sql "SELECT count(*) FROM bindings WHERE item IN (SELECT id FROM items WHERE link_id IN ('old', 'dirty', 'nodate', 'witness', 'full')) AND collection != 'Archive' AND base_object IS NULL AND base_present = 1;")|$(sql "SELECT base_flags_known FROM bindings WHERE item IN (SELECT id FROM items WHERE link_id = 'dirty');")|$(base_flags INBOX dirty imap)" \
    "6|1|"
expect "release: a body held elsewhere stays pinned, the rest fall to the collector" \
    "$(run owner/list_garbage_objects | sort | tr '\n' ' ')|$(sql "SELECT refcount FROM objects WHERE hash = '$h1';")" "$h2 $h3 $h8 |4"
expect "release: each released item moves in the feed" \
    "$(run read/list_items_changed_since ":since=$cursor" ":limit=10" | cut -d'|' -f3 | sort -n | tr '\n' ' ')" "1 2 3 8 9 "
expect "release: a second run finds nothing" \
    "$(run owner/release_bases_before "$set" ":until='2026-09-01T00:00:00Z'")$(run owner/release_before "$set" ":until='2026-09-01T00:00:00Z'")" ""
run owner/release_bases_before "$set" ":until=NULL"
expect "release: no ceiling reaches the newest" \
    "$(run owner/release_before "$set" ":until=NULL")" "4"

# --- A reference joins two endpoints and goes with the last row of one (§14.2)

fresh
collection INBOX
collection Archive
run owner/set_collection_kind ":collection='Cards'" ":account=NULL" ":kind='text/vcard'"
run owner/set_collection_kind ":collection='Cal'" ":account=NULL" ":kind='text/calendar'"
mail INBOX m 1 10 "'2026-10-06T08:00:00Z'"
mail Archive m 1 10 "'2026-10-06T08:00:00Z'"
item Cards alice 2
item Cal ev 3
item Cal same 4
item Cards same 5
item Cards same2 6
item Cal same2 7
item INBOX 'alt:Alert|2026-08-01T10:00:00Z|cron@host' 8
# ref <from_kind> <from_link_id> <to_kind> <to_link_id> <role> <origin>:
# add_reference.
ref() {
    run owner/add_reference ":from_kind='$1'" ":from_link_id='$2'" ":to_kind='$3'" ":to_link_id='$4'" \
        ":role='$5'" ":origin='$6'" | cut -d'|' -f1-6
}
mail_kind=message/rfc822 card_kind=text/vcard cal_kind=text/calendar
cursor="$(run read/load_change_cursor | cut -d'|' -f1)"
expect "reference: recorded between two held endpoints, and answered" \
    "$(ref $mail_kind m $card_kind alice sender auto)" "message/rfc822|m|text/vcard|alice|sender|auto"
expect "reference: read from either end" \
    "$(run read/references_from ":kind='$mail_kind'" ":link_id='m'" | cut -d'|' -f3,4)$(run read/references_to ":kind='$card_kind'" ":link_id='alice'" | cut -d'|' -f1,2)" \
    "text/vcard|alicemessage/rfc822|m"
expect "reference: stamped by SQLite, moving nothing in the feed" \
    "$(sql "SELECT created_at LIKE '____-__-__T__:__:__.___Z' FROM item_reference;")$(run read/list_items_changed_since ":since=$cursor" ":limit=10")" "1"
expect "reference: a duplicate records nothing and answers the reference standing" \
    "$(ref $mail_kind m $card_kind alice sender auto | cut -d'|' -f6)$(sql "SELECT count(*) FROM item_reference;")" "auto1"
expect "reference: a person's takes over a rule's, never the reverse" \
    "$(ref $mail_kind m $card_kind alice sender user | cut -d'|' -f6)$(ref $mail_kind m $card_kind alice sender auto | cut -d'|' -f6)$(sql "SELECT origin FROM item_reference;")" \
    "useruseruser"
expect "reference: an application's x- role is accepted" \
    "$(ref $card_kind alice $cal_kind ev x-moa-thread user | cut -d'|' -f5)" "x-moa-thread"
expect "reference: a role outside the vocabulary, a bare or capital x-, and an unknown origin are refused" \
    "$(fails owner/add_reference ":from_kind='$card_kind'" ":from_link_id='alice'" ":to_kind='$cal_kind'" ":to_link_id='ev'" ":role='friend'" ":origin='user'" && echo r)$(fails owner/add_reference ":from_kind='$card_kind'" ":from_link_id='alice'" ":to_kind='$cal_kind'" ":to_link_id='ev'" ":role='x-'" ":origin='user'" && echo b)$(fails owner/add_reference ":from_kind='$card_kind'" ":from_link_id='alice'" ":to_kind='$cal_kind'" ":to_link_id='ev'" ":role='X-a'" ":origin='user'" && echo c)$(fails owner/add_reference ":from_kind='$card_kind'" ":from_link_id='alice'" ":to_kind='$cal_kind'" ":to_link_id='ev'" ":role='related'" ":origin='robot'" && echo o)" \
    "rbco"
expect "reference: an endpoint the store holds no row of, under that kind, records nothing" \
    "$(ref $mail_kind m $card_kind ghost related user)$(ref $mail_kind m $cal_kind alice related user)" ""
expect "reference: the from end is matched under its kind too" \
    "$(ref $card_kind m $card_kind alice related user)" ""
expect "reference: a writer-derived key is no endpoint: recorded by nothing, refused by the schema" \
    "$(ref $mail_kind 'alt:Alert|2026-08-01T10:00:00Z|cron@host' $card_kind alice related user)$(sql "INSERT INTO item_reference VALUES('$mail_kind', 'dup:m#1', '$card_kind', 'alice', 'related', 'user', 't');" 2>&1 | grep -c CHECK)$(sql "INSERT INTO item_reference VALUES('$card_kind', 'alice', 'application/octet-stream', 'part:alt:x#2', 'attachment', 'auto', 't');" 2>&1 | grep -c CHECK)" "11"
expect "reference: an item never refers to itself" \
    "$(fails owner/add_reference ":from_kind='$cal_kind'" ":from_link_id='ev'" ":to_kind='$cal_kind'" ":to_link_id='ev'" ":role='related'" ":origin='user'" && echo refused)" "refused"
expect "reference: removed by a plain delete, once" \
    "$(run owner/remove_reference ":from_kind='$card_kind'" ":from_link_id='alice'" ":to_kind='$cal_kind'" ":to_link_id='ev'" ":role='x-moa-thread'" | cut -d'|' -f5)$(run owner/remove_reference ":from_kind='$card_kind'" ":from_link_id='alice'" ":to_kind='$cal_kind'" ":to_link_id='ev'" ":role='x-moa-thread'")" \
    "x-moa-thread"
ref $mail_kind m $cal_kind ev invitation auto >/dev/null
ref $card_kind alice $cal_kind same related user >/dev/null
ref $cal_kind ev $card_kind same related user >/dev/null
run owner/rename_collection ":collection='INBOX'" ":new_id='Inbox'"
sql "DELETE FROM items WHERE collection = 'Inbox' AND link_id = 'm';"
expect "reference: a rename keeps it, and a copy deleted elsewhere too" \
    "$(run read/references_from ":kind='$mail_kind'" ":link_id='m'" | cut -d'|' -f5 | tr '\n' ' ')" "sender invitation "
sql "UPDATE items SET deleted = 1, retained_at = 'x' WHERE collection = 'Archive' AND link_id = 'm';"
expect "reference: a tombstoned or retained last row still holds it" \
    "$(run read/references_from ":kind='$mail_kind'" ":link_id='m'" | wc -l | tr -d ' ')" "2"
run owner/purge_item ":collection='Archive'" ":seq=1" >/dev/null
expect "reference: the purge of the last row takes every reference of the endpoint" \
    "$(run read/references_from ":kind='$mail_kind'" ":link_id='m'")$(run read/references_to ":kind='$cal_kind'" ":link_id='ev'")" ""
sql "DELETE FROM items WHERE collection = 'Cards' AND link_id = 'same';"
expect "reference: the kind is in the endpoint, another kind's row under the same link id holding nothing" \
    "$(run read/references_to ":kind='$cal_kind'" ":link_id='same'" | cut -d'|' -f2)|$(run read/references_to ":kind='$card_kind'" ":link_id='same'")" "alice|"
ref $card_kind same2 $cal_kind ev related user >/dev/null
sql "DELETE FROM items WHERE collection = 'Cards' AND link_id = 'same2';"
expect "reference: the from end goes by its kind, another kind's row under its link id holding nothing" \
    "$(run read/references_to ":kind='$cal_kind'" ":link_id='ev'")" ""
expect "reference: every reference's endpoints are held, by the schema's trigger" \
    "$(sql "SELECT count(*) FROM item_reference r WHERE NOT EXISTS (SELECT 1 FROM items i JOIN collections c ON c.id = i.collection WHERE i.link_id = r.from_link_id AND c.kind = r.from_kind) OR NOT EXISTS (SELECT 1 FROM items i JOIN collections c ON c.id = i.collection WHERE i.link_id = r.to_link_id AND c.kind = r.to_kind);")" "0"
run owner/delete_collection ":collection='Cards'"
expect "reference: a collection's delete takes the references of the endpoints it held last" \
    "$(sql "SELECT count(*) FROM item_reference;")" "0"

# --- Automatic references run from the mail to what it names (§14.2) --------

fresh
collection INBOX
run owner/set_collection_kind ":collection='Cards'" ":account=NULL" ":kind='$card_kind'"
run owner/set_collection_kind ":collection='Cal'" ":account=NULL" ":kind='$cal_kind'"
for n in 1 2 3 4 5 6 7 8; do
    mail INBOX m$n $n 1$n "'2026-10-06T0$n:00:00Z'"
done
mail INBOX 'alt:Alert|2026-08-01T10:00:00Z|cron@host' 20 30 "'2026-10-06T09:00:00Z'"
item Cards c1 9
item Cards c2 10
item Cards c3 11
item Cards ev4 12
item Cal ev1 13
item Cal ev3 14
sql "INSERT INTO item_address(item, role, position, address) VALUES
         ((SELECT id FROM items WHERE collection = 'INBOX' AND link_id = 'm1'), 'from', 0, 'alice@example.org'), ((SELECT id FROM items WHERE collection = 'INBOX' AND link_id = 'm2'), 'from', 0, 'bob@example.org'),
         ((SELECT id FROM items WHERE collection = 'INBOX' AND link_id = 'm3'), 'from', 0, 'alice@example.org'), ((SELECT id FROM items WHERE collection = 'INBOX' AND link_id = 'm1'), 'to', 0, 'carol@example.org'),
         ((SELECT id FROM items WHERE collection = 'INBOX' AND link_id = 'alt:Alert|2026-08-01T10:00:00Z|cron@host'), 'from', 0, 'alice@example.org'),
         ((SELECT id FROM items WHERE collection = 'Cards' AND link_id = 'c1'), 'email', 0, 'alice@example.org'), ((SELECT id FROM items WHERE collection = 'Cards' AND link_id = 'c2'), 'email', 0, 'carol@example.org'),
         ((SELECT id FROM items WHERE collection = 'Cards' AND link_id = 'c3'), 'email', 0, 'alice@example.org');
     UPDATE items SET deleted = 1 WHERE link_id IN ('m3', 'm6', 'c3', 'ev3');
     UPDATE mail_summary SET invitation = 'ev1' WHERE item IN (SELECT id FROM items WHERE link_id IN ('m4', 'm6'));
     UPDATE mail_summary SET invitation = 'ev2' WHERE item IN (SELECT id FROM items WHERE link_id = 'm5');
     UPDATE mail_summary SET invitation = 'ev3' WHERE item IN (SELECT id FROM items WHERE link_id = 'm7');
     UPDATE mail_summary SET invitation = 'ev4' WHERE item IN (SELECT id FROM items WHERE link_id = 'm8');"
refs() {
    sql "SELECT from_link_id || '>' || to_link_id || ':' || role || ':' || origin FROM item_reference ORDER BY 1;" | tr '\n' ' '
}
user() {
    run owner/add_reference ":from_kind='$mail_kind'" ":from_link_id='$1'" ":to_kind='$2'" ":to_link_id='$3'" ":role='$4'" ":origin='user'" >/dev/null
}
run owner/link_senders_of ":link_id='m1'"
expect "auto: a mail refers to the live contact its from address names, never through another role" \
    "$(refs)" "m1>c1:sender:auto "
run owner/link_senders_of ":link_id='m3'"
run owner/link_senders_of ":link_id='alt:Alert|2026-08-01T10:00:00Z|cron@host'"
expect "auto: a deleted mail, and one under a derived key, refer to nobody" "$(refs)" "m1>c1:sender:auto "
run owner/link_mail_from ":link_id='c1'"
run owner/link_mail_from ":link_id='c3'"
expect "auto: a contact's backfill takes live mail only, and a deleted contact takes none" "$(refs)" "m1>c1:sender:auto "
user m2 $card_kind c2 sender
sql "INSERT INTO item_address(item, role, position, address) VALUES((SELECT id FROM items WHERE collection = 'Cards' AND link_id = 'c2'), 'email', 1, 'bob@example.org');"
run owner/link_mail_from ":link_id='c2'"
expect "auto: an address added brings its history, a person's reference kept as it is" \
    "$(refs)" "m1>c1:sender:auto m2>c2:sender:user "
sql "DELETE FROM item_address WHERE item IN (SELECT id FROM items WHERE link_id = 'c1');"
run owner/link_mail_from ":link_id='c1'"
expect "auto: an address removed removes nothing" "$(refs)" "m1>c1:sender:auto m2>c2:sender:user "
sql "DELETE FROM item_reference;
     UPDATE items SET deleted = 0 WHERE link_id = 'c3';"
user m2 $card_kind c2 sender
run owner/link_senders_of ":link_id=NULL"
expect "auto: a NULL link id backfills every live mail, a person's reference kept as it is" \
    "$(refs)" "m1>c3:sender:auto m2>c2:sender:user "
sql "DELETE FROM item_reference;"
user m4 $cal_kind ev1 invitation
for n in 4 5 6 7 8; do
    run owner/link_invitations_of ":link_id='m$n'"
done
for e in ev1 ev3 ev4; do
    run owner/link_invitations_to ":link_id='$e'"
done
expect "auto: an invitation refers to the live calendar item it names, a person's kept, none for one not held, deleted or of another kind" \
    "$(refs)" "m4>ev1:invitation:user "
item Cal ev2 15
run owner/link_invitations_to ":link_id='ev2'"
expect "auto: a calendar item synced after its invitation is tied to it, never to a deleted mail" \
    "$(refs)" "m4>ev1:invitation:user m5>ev2:invitation:auto "
run owner/upsert_mail_summary ":collection='INBOX'" ":link_id='m4'" ":message_id='m4'" ":in_reply_to='[]'" \
    ":subject='s m4'" ":sender='alice@example.org'" ":sender_name='Alice'" ":date=NULL" ":size=1" ":attachment=0" ":invitation=NULL"
expect "auto: a write without the body keeps a known invitation" \
    "$(sql "SELECT invitation FROM mail_summary WHERE item IN (SELECT id FROM items WHERE link_id = 'm4');")" "ev1"
for statement in link_senders_of link_mail_from link_invitations_of; do
    expect "auto: $statement seeks one link id" \
        "$(plan "owner/$statement" ":link_id='m1'" | grep -c 'items_by_link (link_id>? AND link_id<?)' || true)" "1"
done
expect "auto: link_invitations_to seeks the invitation" \
    "$(plan owner/link_invitations_to ":link_id='ev1'" | grep -c 'mail_summary_by_invitation' || true)" "1"

# --- A task refers to its parent and to the mail it came from (§14.2) -------

fresh
collection INBOX
run owner/set_collection_kind ":collection='Cal'" ":account=NULL" ":kind='$cal_kind'"
run owner/set_collection_kind ":collection='Cards'" ":account=NULL" ":kind='$card_kind'"
# task <link_id> <seq> <parent> <mid>: a live task naming both, or NULL.
task() {
    item Cal "$1" "$2"
    run owner/upsert_task_summary ":collection='Cal'" ":link_id='$1'" ":uid='$1'" ":summary='t $1'" \
        ":dtstart=NULL" ":dtstart_tzid=NULL" ":dtstart_value=NULL" ":due=NULL" ":due_tzid=NULL" \
        ":due_value=NULL" ":status=NULL" ":completed=NULL" ":percent=NULL" ":recurring=0" \
        ":until=NULL" ":priority=NULL" ":categories='[]'" ":parent=$3" ":mid=$4"
}
refs() {
    sql "SELECT from_link_id || '>' || to_link_id || ':' || role || ':' || origin FROM item_reference ORDER BY 1;" | tr '\n' ' '
}
mail INBOX m1 1 11 NULL
mail INBOX m2 2 12 NULL
item Cards card 3
task proj 4 NULL NULL
task t1 5 "'proj'" "'m1'"
task t2 6 "'gone'" "'m9'"
task t3 7 "'proj'" "'m2'"
task t4 8 "'t4'" NULL
task t5 20 "'card'" NULL
task t6 21 NULL "'card'"
sql "UPDATE items SET deleted = 1 WHERE link_id = 't3';"
for t in t1 t2 t3 t4 t5 t6; do
    run owner/link_parents_of ":link_id='$t'"
    run owner/link_sources_of ":link_id='$t'"
done
expect "auto: a task refers to its live parent calendar item and its live mail, never to one not held, of another kind, itself, nor from a deleted task" \
    "$(refs)" "t1>m1:source:auto t1>proj:parent:auto "
sql "DELETE FROM item_reference;"
run owner/add_reference ":from_kind='$cal_kind'" ":from_link_id='t1'" ":to_kind='$cal_kind'" ":to_link_id='proj'" ":role='parent'" ":origin='user'" >/dev/null
run owner/link_parents_to ":link_id='proj'"
run owner/link_sources_to ":link_id='m1'"
run owner/link_sources_to ":link_id='m2'"
expect "auto: a parent and a mail backfill their tasks, a person's reference kept, a deleted task taking none" \
    "$(refs)" "t1>m1:source:auto t1>proj:parent:user "
item Cal gone 9
mail INBOX m9 10 19 NULL
run owner/link_parents_to ":link_id='gone'"
run owner/link_sources_to ":link_id='m9'"
expect "auto: a parent and a mail synced after the task are tied to it" \
    "$(refs)" "t1>m1:source:auto t1>proj:parent:user t2>gone:parent:auto t2>m9:source:auto "
sql "DELETE FROM item_reference;"
run owner/link_parents_of ":link_id=NULL"
run owner/link_sources_of ":link_id=NULL"
expect "auto: a NULL link id backfills every live task" \
    "$(refs)" "t1>m1:source:auto t1>proj:parent:auto t2>gone:parent:auto t2>m9:source:auto "
for statement in link_parents_of link_sources_of; do
    expect "auto: $statement seeks one link id" \
        "$(plan "owner/$statement" ":link_id='t1'" | grep -c 'items_by_link (link_id>? AND link_id<?)' || true)" "1"
done
expect "auto: link_parents_to seeks the parent" \
    "$(plan owner/link_parents_to ":link_id='proj'" | grep -c 'task_summary_by_parent' || true)" "1"
expect "auto: link_sources_to seeks the mail" \
    "$(plan owner/link_sources_to ":link_id='m1'" | grep -c 'task_summary_by_mid' || true)" "1"
expect "task: a priority out of RFC 5545's range is refused" \
    "$(fails owner/upsert_task_summary ":collection='Cal'" ":link_id='t1'" ":uid='t1'" ":summary='t'" \
        ":dtstart=NULL" ":dtstart_tzid=NULL" ":dtstart_value=NULL" ":due=NULL" ":due_tzid=NULL" \
        ":due_value=NULL" ":status=NULL" ":completed=NULL" ":percent=NULL" ":recurring=0" \
        ":until=NULL" ":priority=10" ":categories='[]'" ":parent=NULL" ":mid=NULL" && echo refused)" "refused"

# --- A file stands for an attachment until no reference names it (§14.3) ----

fresh
file_kind=application/octet-stream
collection work/INBOX work
for folder in work/Attachments work/Docs; do
    run owner/set_collection_kind ":collection='$folder'" ":account='work'" ":kind='$file_kind'"
done
object "$hx"
mail work/INBOX m 1 10 "'2026-10-06T08:00:00Z'"
# file <collection> <link_id> <seq> <object|NULL> <name> <part|NULL> [bound]
file() {
    run owner/insert_item ":collection='$1'" ":link_id='$2'" ":seq=$3" ":flags='[]'" ":object_hash=$4" \
        ":sort_key='$(tr '[:upper:]' '[:lower:]' <<<"$5")'" ":level=$([ "$4" = NULL ] && echo 1 || echo 2)" \
        ":deleted=0" ":conflicted=0" ":conflict_object=NULL"
    run owner/upsert_file_summary ":collection='$1'" ":link_id='$2'" ":name='$5'" ":media_type='application/pdf'" \
        ":size=1234" ":part=$6"
    if [ -n "${7:-}" ]; then
        sql "INSERT INTO bindings(item, collection, source, handle, base_present) VALUES((SELECT id FROM items WHERE collection = '$1' AND link_id = '$2'), '$1', 'dav', '$2', 1);"
    fi
}
file work/Attachments 'part:m#2' 2 NULL Report.pdf "'2'"
file work/Attachments 'part:m#3' 3 NULL photo.jpg "'3'"
file work/Docs local 4 "'$hx'" notes.txt NULL
file work/Docs synced 5 NULL remote.txt NULL bound
run owner/recompute_refcounts
for part in 'part:m#2' 'part:m#3'; do
    ref $mail_kind m $file_kind "$part" attachment auto >/dev/null
done
expect "file: a blob-less file is a Meta item with its summary" \
    "$(run read/get_file ":collection='work/Attachments'" ":seq=2" | cut -d'|' -f4,6,7,8,9,10)" "|1|Report.pdf|application/pdf|1234|2"
expect "file: a folder lists A to Z on the name" \
    "$(run read/list_files_page_asc ":collection='work/Attachments'" ":after_key=''" ":after_seq=0" ":limit=10" | cut -d'|' -f7 | tr '\n' ' ')" \
    "photo.jpg Report.pdf "
expect "file: a message's attachments in the order recorded, with their part" \
    "$(run read/list_attachments ":account='work'" ":link_id='m'" | cut -d'|' -f1,4,7,8 | tr '\n' ' ')" \
    "part:m#2|Report.pdf|2| part:m#3|photo.jpg|3| "
file work/Docs 'part:m#2' 2 "'$hx'" 'Q3 report.pdf' "'2'"
expect "file: saved to a folder, the stand-in still reads, held by the saved copy's body" \
    "$(run read/list_attachments ":account='work'" ":link_id='m'" | head -1 | cut -d'|' -f2,4,8)" "work/Attachments|Report.pdf|$hx"
expect "file: one public id for the stand-in and the saved copy" \
    "$(sql "SELECT count(DISTINCT seq) FROM items WHERE link_id = 'part:m#2';")" "1"
run owner/set_collection_role ":collection='work/Attachments'" ":role='attachments'"
expect "file: the attachments role marks a file collection" \
    "$(sql "SELECT role FROM collections WHERE id = 'work/Attachments';")" "attachments"
expect "file: every stand-in of an account with its message, newest first, paged" \
    "$(run read/list_attachments_by_account ":account='work'" ":after_key=NULL" ":after_seq=NULL" ":limit=10" | cut -d'|' -f3,8,12 | tr '\n' ' ')|$(run read/list_attachments_by_account ":account='work'" ":after_key=''" ":after_seq=3" ":limit=10" | cut -d'|' -f3)" \
    "part:m#3|m|alice@example.org part:m#2|m|alice@example.org |part:m#2"
steps="$(plan read/list_attachments_by_account ":account='work'" ":after_key=NULL" ":after_seq=NULL" ":limit=10")"
expect "file: every stand-in of an account is read from its attachments collection, found by its role, never from every item" \
    "$(grep -c 'SEARCH c USING INDEX collections_by_role' <<<"$steps" || true)$(grep -c 'SCAN' <<<"$steps" || true)" "10"
for folder in home/Attachments home/Docs; do
    run owner/set_collection_kind ":collection='$folder'" ":account='home'" ":kind='$file_kind'"
done
file home/Attachments 'part:m#2' 2 NULL Report.pdf "'2'"
file home/Attachments 'part:m#3' 3 NULL photo.jpg "'3'"
file work/Docs 'part:m#3' 3 "'$hx'" photo.jpg "'3'"
sql "UPDATE items SET deleted = 1 WHERE collection IN ('home/Attachments', 'work/Docs') AND link_id = 'part:m#3';"
ref $mail_kind m $file_kind local related user >/dev/null
expect "file: a message's attachments are the account's, live, by the attachment role, held by a live body only" \
    "$(run read/list_attachments ":account='home'" ":link_id='m'" | cut -d'|' -f1,2 | tr '\n' ' ')|$(run read/list_attachments ":account='work'" ":link_id='m'" | cut -d'|' -f1,8 | tr '\n' ' ')" \
    "part:m#2|home/Attachments |part:m#2|$hx part:m#3| "
expect "file: a file another account holds under the same key never reads as held" \
    "$(run read/list_attachments ":account='home'" ":link_id='m'" | cut -d'|' -f1,8 | tr '\n' ' ')" "part:m#2| "
run owner/remove_reference ":from_kind='$mail_kind'" ":from_link_id='m'" ":to_kind='$file_kind'" ":to_link_id='local'" ":role='related'" >/dev/null
run owner/insert_item ":collection='work/INBOX'" ":link_id='part:m#3'" ":seq=3" ":flags='[]'" ":object_hash=NULL" \
    ":sort_key=''" ":level=1" ":deleted=0" ":conflicted=0" ":conflict_object=NULL"
run owner/add_reference ":from_kind='$file_kind'" ":from_link_id='part:m#3'" ":to_kind='$file_kind'" ":to_link_id='local'" ":role='related'" ":origin='user'" >/dev/null
run owner/remove_reference ":from_kind='$mail_kind'" ":from_link_id='m'" ":to_kind='$file_kind'" ":to_link_id='part:m#3'" ":role='attachment'" >/dev/null
expect "file: a stand-in a reference still names from its own end stays" \
    "$(sql "SELECT count(*) FROM items WHERE collection = 'work/Attachments' AND link_id = 'part:m#3';")" "1"
run owner/remove_reference ":from_kind='$file_kind'" ":from_link_id='part:m#3'" ":to_kind='$file_kind'" ":to_link_id='local'" ":role='related'" >/dev/null
expect "file: a stand-in no reference names is collected, never a row of another kind under its key" \
    "$(sql "SELECT group_concat(collection) FROM items WHERE link_id = 'part:m#3' AND (deleted = 0 OR object_hash IS NOT NULL);")" "work/Docs,work/INBOX"
for target in local synced; do
    ref $mail_kind m $file_kind $target related user >/dev/null
    run owner/remove_reference ":from_kind='$mail_kind'" ":from_link_id='m'" ":to_kind='$file_kind'" ":to_link_id='$target'" ":role='related'" >/dev/null
done
expect "file: a file holding a body, or bound by a source, is never collected for want of a reference" \
    "$(sql "SELECT link_id FROM items WHERE link_id IN ('local', 'synced') ORDER BY link_id;" | tr '\n' ' ')" "local synced "
sql "UPDATE items SET deleted = 1, retained_at = 'x' WHERE link_id = 'm';"
run owner/purge_item ":collection='work/INBOX'" ":seq=1" >/dev/null
expect "file: the message's last row gone, its stand-in goes and the saved copy stays with its body" \
    "$(sql "SELECT collection || ':' || ifnull(object_hash, '') FROM items WHERE link_id = 'part:m#2';")|$(sql "SELECT count(*) FROM item_reference;")" \
    "work/Docs:$hx|0"
steps="$(trigger_plan item_reference_collects_files ":old_from_kind='$mail_kind'" ":old_from_link_id='m'" ":old_to_kind='$file_kind'" ":old_to_link_id='x'")"
expect "file: the collecting trigger seeks the ends' link ids, never every bodiless row" \
    "$(grep -c 'items USING INDEX items_by_link' <<<"$steps" || true)$(grep -c 'items_by_object' <<<"$steps" || true)" "10"
steps="$(trigger_plan items_drop_references ":old_link_id='m'")"
expect "reference: the dropping trigger seeks both ends' keys" \
    "$(grep -c 'SCAN item_reference' <<<"$steps" || true)" "0"
run owner/upsert_file_summary ":collection='work/Docs'" ":link_id='part:m#2'" ":name='Q3 report.pdf'" ":media_type='application/pdf'" ":size=1234" ":part='2.1'"
expect "file: a summary write restates the part" \
    "$(run read/get_file ":collection='work/Docs'" ":seq=2" | cut -d'|' -f10)" "2.1"
expect "file: a collection holding no object pointer can skip the recount" \
    "$(run owner/collection_holds_objects ":collection='work/Attachments'")$(run owner/collection_holds_objects ":collection='work/Docs'")" "01"
expect "file: an unbound file is deleted with the hashes to release, a bound one is its source's" \
    "$(run owner/delete_unbound_item ":collection='work/Docs'" ":link_id='local'" | cut -d'|' -f1)|$(run owner/delete_unbound_item ":collection='work/Docs'" ":link_id='synced'")|$(sql "SELECT count(*) FROM items WHERE link_id IN ('local', 'synced');")" \
    "$hx||1"

# --- The local time collection holds unbound time entries (§14.3) -----------

fresh
time_id=$'\x01time'
run owner/set_collection_kind ":collection='$time_id'" ":account=NULL" ":kind='$cal_kind'"
run owner/set_collection_name ":collection='$time_id'" ":account=NULL" ":name='time'"
object "$he"
object "$hj"
item "$time_id" entry 1 "'$he'"
run owner/upsert_event_summary ":collection='$time_id'" ":link_id='entry'" ":uid='entry'" ":summary='Paint the hallway'" \
    ":location=NULL" ":dtstart='2026-10-28T09:00:00Z'" ":dtstart_tzid=NULL" ":dtstart_value=NULL" ":dtend=NULL" \
    ":recurring=0" ":until=NULL"
item "$time_id" start 2 "'$hj'"
run owner/upsert_journal_summary ":collection='$time_id'" ":link_id='start'" ":uid='start'" ":summary='Paint the hallway'" \
    ":dtstart='2026-10-28T09:00:00Z'" ":dtstart_tzid=NULL" ":dtstart_value=NULL"
expect "time: the local time collection is a calendar collection under no account, no source syncing it" \
    "$(run read/list_collections_by_account ":account=NULL" | cut -d'|' -f2,3,4 | tr -d '\001')|$(run owner/collection_sources ":collection='$time_id'")" \
    "|text/calendar|time|"
expect "time: a running entry is an event with no end, a journal entry has its instant" \
    "$(sql "SELECT ifnull(dtend, 'running') FROM event_summary WHERE item IN (SELECT id FROM items WHERE link_id = 'entry');")|$(sql "SELECT dtstart FROM journal_summary WHERE item IN (SELECT id FROM items WHERE link_id = 'start');")" \
    "running|2026-10-28T09:00:00Z"
expect "time: an entry no source binds is deleted with its summary and the hash to release" \
    "$(run owner/delete_unbound_item ":collection='$time_id'" ":link_id='entry'" | cut -d'|' -f1)|$(sql "SELECT count(*) FROM event_summary;")|$(run owner/delete_unbound_item ":collection='$time_id'" ":link_id='start'" | cut -d'|' -f1)|$(sql "SELECT count(*) FROM items;")" \
    "$he|0|$hj|0"

# --- An action on an item no source binds is the store's to settle (§15.3) --

fresh
collection Local
collection INBOX
run owner/upsert_checkpoint ":collection='INBOX'" ":source='imap'" ":checkpoint=NULL"
object "$hn"
item Local note 1 "'$hn'"
item Local gone 2 "'$hn'"
item INBOX fresh 3 "'$hn'"
expect "unbound: a collection no source syncs answers none, one whose source holds a checkpoint and no binding answers it, and no source binds either item" \
    "$(run owner/collection_sources ":collection='Local'")|$(run owner/collection_sources ":collection='INBOX'")|$(run read/list_item_bindings ":collection='Local'" ":link_id='note'")$(run read/list_item_bindings ":collection='INBOX'" ":link_id='fresh'")" \
    "|imap|"
before="$(sql "SELECT changed FROM items WHERE link_id = 'note';")"
run owner/update_item ":collection='Local'" ":link_id='note'" ":flags='[\"\\\\Flagged\"]'" ":object_hash='$hn'" ":sort_key=''" \
    ":level=2" ":deleted=0" ":conflicted=0" ":conflict_object=NULL"
run owner/retain_item ":collection='Local'" ":link_id='gone'" ":source='owner'"
expect "unbound: a set-flags applies to the item directly and moves its stamp; a remove retains it, its body still pinned" \
    "$(flags Local note)|$(sql "SELECT changed > $before FROM items WHERE link_id = 'note';")|$(sql "SELECT deleted, retained_at IS NOT NULL, object_hash FROM items WHERE link_id = 'gone';")|$(run read/count_retained ":collection='Local'")" \
    "\\Flagged|1|1|1|$hn|1"

# --- An add superseding an item holds its delete until it is pushed (§15.3) --

# bind <collection> <link_id> <source> <handle> <base_present>: one binding,
# with a base or none.
bind() {
    local base="NULL"
    [ "$5" = 1 ] && base="'[]'"
    run owner/insert_binding ":collection='$1'" ":link_id='$2'" ":source='$3'" ":handle='$4'" \
        ":base_flags=$base" ":base_object=NULL" ":base_revision=NULL" ":base_present=$5" \
        ":conflicted=0" ":conflict_revision=NULL" ":conflict_object=NULL" ":shared_object=NULL"
}

fresh
run owner/set_collection_kind ":collection='tasks-a'" ":account=NULL" ":kind='$cal_kind'"
run owner/set_collection_kind ":collection='tasks-b'" ":account=NULL" ":kind='$cal_kind'"
object "$ht"
object "$hn"
item tasks-a t1 1 "'$ht'"
bind tasks-a t1 caldav a.ics 1
sql "UPDATE items SET deleted = 1 WHERE collection = 'tasks-a' AND link_id = 't1';"
item tasks-b n1 2 "'$hn'"
bind tasks-b n1 caldav $'\x01n1' 0
run owner/supersede_item ":collection='tasks-a'" ":link_id='t1'" ":by_collection='tasks-b'" ":by_link_id='n1'"
expect "supersedes: a pending superseding create holds the tombstone" \
    "$(run owner/list_superseded_pending ":collection='tasks-a'")" "t1"
expect "supersedes: nothing is held in the superseding collection" \
    "$(run owner/list_superseded_pending ":collection='tasks-b'")" ""
sql "UPDATE bindings SET handle = 'n1.ics', base_flags_known = 1, base_present = 1 WHERE collection = 'tasks-b';"
expect "supersedes: the create accepted releases the hold" \
    "$(run owner/list_superseded_pending ":collection='tasks-a'")" ""
run owner/delete_item_bindings ":collection='tasks-b'" ":link_id='n1'"
expect "supersedes: a collection no source syncs has no create to wait for" \
    "$(run owner/list_superseded_pending ":collection='tasks-a'")" ""
run owner/upsert_checkpoint ":collection='tasks-b'" ":source='caldav'" ":checkpoint=NULL"
expect "supersedes: a source syncing it by its checkpoint alone and binding nothing of a body holds it again" \
    "$(run owner/list_superseded_pending ":collection='tasks-a'")" "t1"
run owner/retain_item ":collection='tasks-b'" ":link_id='n1'" ":source='caldav'"
expect "supersedes: the superseding create withdrawn releases the hold" \
    "$(run owner/list_superseded_pending ":collection='tasks-a'")" ""
sql "UPDATE items SET deleted = 0, retained_at = NULL, retained_by = NULL WHERE collection = 'tasks-b';"
run owner/supersede_item ":collection='tasks-a'" ":link_id='t1'" ":by_collection='tasks-b'" ":by_link_id='n1'"
expect "supersedes: a second record of the pair is one row" "$(sql "SELECT count(*) FROM supersessions;")" "1"
sql "UPDATE items SET deleted = 0 WHERE collection = 'tasks-a';"
expect "supersedes: a revived item is no tombstone to hold" \
    "$(run owner/list_superseded_pending ":collection='tasks-a'")" ""
sql "UPDATE items SET deleted = 1 WHERE collection = 'tasks-a';"
run owner/rename_collection ":collection='tasks-b'" ":new_id='tasks-c'"
expect "supersedes: a rename of the superseding collection cascades into the pair" \
    "$(sql "SELECT i.collection FROM supersessions s JOIN items i ON i.id = s.by_item;")|$(run owner/list_superseded_pending ":collection='tasks-a'")" "tasks-c|t1"
sql "DELETE FROM items WHERE collection = 'tasks-c';"
expect "supersedes: the superseding row gone takes the pair" "$(sql "SELECT count(*) FROM supersessions;")" "0"

# --- A superseding create of the same identity names what to move (§15.3) --

fresh
run owner/set_collection_kind ":collection='tasks-a'" ":account=NULL" ":kind='$cal_kind'"
run owner/set_collection_kind ":collection='tasks-b'" ":account=NULL" ":kind='$cal_kind'"
object "$ht"
object "$hn"
item tasks-a t1 1 "'$ht'"
bind tasks-a t1 caldav a.ics 1
sql "UPDATE bindings SET base_revision = 'r1' WHERE collection = 'tasks-a';"
sql "UPDATE items SET deleted = 1 WHERE collection = 'tasks-a' AND link_id = 't1';"
item tasks-b t1 2 "'$hn'"
bind tasks-b t1 caldav $'\x01t1' 0
run owner/supersede_item ":collection='tasks-a'" ":link_id='t1'" ":by_collection='tasks-b'" ":by_link_id='t1'"
expect "supersedes: a create keeping the identity names the binding it may be moved from" \
    "$(run owner/list_superseded_bindings ":collection='tasks-b'" ":source='caldav'")" "t1|tasks-a|a.ics|r1"
expect "supersedes: another source binds nothing to move" \
    "$(run owner/list_superseded_bindings ":collection='tasks-b'" ":source='other'")" ""
expect "supersedes: the superseded collection has nothing to move in" \
    "$(run owner/list_superseded_bindings ":collection='tasks-a'" ":source='caldav'")" ""
item tasks-b n1 3 "'$hn'"
item tasks-a t2 4 "'$ht'"
bind tasks-a t2 caldav b.ics 1
sql "UPDATE items SET deleted = 1 WHERE collection = 'tasks-a' AND link_id = 't2';"
run owner/supersede_item ":collection='tasks-a'" ":link_id='t2'" ":by_collection='tasks-b'" ":by_link_id='n1'"
expect "supersedes: a create of another identity is a plain create" \
    "$(run owner/list_superseded_bindings ":collection='tasks-b'" ":source='caldav'")" "t1|tasks-a|a.ics|r1"
sql "UPDATE items SET deleted = 0 WHERE collection = 'tasks-a' AND link_id = 't1';"
expect "supersedes: a revived item is no member to move" \
    "$(run owner/list_superseded_bindings ":collection='tasks-b'" ":source='caldav'")" ""
sql "UPDATE items SET deleted = 1 WHERE collection = 'tasks-a' AND link_id = 't1';"
sql "UPDATE bindings SET handle = 'a.ics', base_flags_known = 1, base_present = 1 WHERE collection = 'tasks-b' AND item IN (SELECT id FROM items WHERE link_id = 't1');"
expect "supersedes: the create accepted has nothing left to move" \
    "$(run owner/list_superseded_bindings ":collection='tasks-b'" ":source='caldav'")" ""

fresh
run owner/set_collection_kind ":collection='tasks-a'" ":account=NULL" ":kind='$cal_kind'"
run owner/set_collection_kind ":collection='tasks-b'" ":account=NULL" ":kind='$cal_kind'"
object "$h1"
run queue/enqueue_action ":producer='p'" ":collection='tasks-b'" ":action='add'" \
    ":payload='{\"v\":1,\"flags\":[],\"object\":\"$h1\",\"supersedes\":{\"collection\":\"tasks-a\",\"seq\":1}}'" ":target_collection='tasks-a'" ":object_hash='$h1'"
run queue/enqueue_action ":producer='p'" ":collection='tasks-b'" ":action='add'" ":payload='{\"v\":1,\"flags\":[],\"object\":\"$h1\"}'" ":object_hash='$h1'"
run owner/rename_queue_targets ":collection='tasks-a'" ":new_id='tasks-2026'"
run owner/rename_collection ":collection='tasks-a'" ":new_id='tasks-2026'"
expect "supersedes: a rename follows into a pending add's supersedes, and leaves a plain add alone" \
    "$(sql "SELECT ifnull(target_collection, '-') FROM queue ORDER BY id;" | tr '\n' ' ')" "tasks-2026 - "

# --- A task's source mail answered is a reply another mail names (§14.1) ----

# reply <link_id> <position> <msg_id>: one In-Reply-To id of a mail.
reply() {
    run owner/insert_in_reply_to ":collection='$(sql "SELECT collection FROM items WHERE link_id = '$1';")'" \
        ":link_id='$1'" ":position=$2" ":msg_id='$3'"
}

fresh
collection INBOX
collection Sent
run owner/set_collection_role ":collection='Sent'" ":role='sent'"
mail INBOX r1 1 10 NULL
reply r1 0 other@x
reply r1 1 asked@x
mail Sent r2 2 11 NULL
reply r2 0 mine@x
mail INBOX r3 3 12 NULL
reply r3 0 gone@x
sql "UPDATE items SET deleted = 1 WHERE link_id = 'r3';"
mail INBOX r4 4 13 NULL
reply r4 0 asked@x
expect "replied: an id a live mail answers, once; the person's own reply and a deleted one answer nothing" \
    "$(run read/list_replied ":ids='[\"asked@x\",\"mine@x\",\"gone@x\",\"never@x\"]'" | tr '\n' ' ')" "asked@x "

# --- A link picker reads one statement per kind (§14.1, §14.2) -------------

fresh
collection INBOX
run owner/set_collection_kind ":collection='Cards'" ":account=NULL" ":kind='$card_kind'"
run owner/set_collection_kind ":collection='Cal'" ":account=NULL" ":kind='$cal_kind'"
run owner/set_collection_kind ":collection='Docs'" ":account=NULL" ":kind='$file_kind'"
mail INBOX m 1 10 "'2026-10-06T08:00:00Z'"
item Cards jane 2
item Cards bob 3
item Cal ev 4
item Cal todo 5
item Cal note 6
item Docs plan 7
sql "UPDATE items SET sort_key = CASE link_id WHEN 'jane' THEN 'jane doe' WHEN 'bob' THEN 'bob' WHEN 'plan' THEN 'plan.pdf' ELSE sort_key END;
     INSERT INTO item_address(item, role, position, address) VALUES((SELECT id FROM items WHERE collection = 'Cards' AND link_id = 'bob'), 'email', 0, 'bob@plan.example');"
run owner/upsert_contact_summary ":collection='Cards'" ":link_id='jane'" ":uid='jane'" ":fn='Jane Doe'" ":kind=NULL" ":org=NULL"
run owner/upsert_contact_summary ":collection='Cards'" ":link_id='bob'" ":uid='bob'" ":fn='Bob'" ":kind=NULL" ":org=NULL"
run owner/upsert_event_summary ":collection='Cal'" ":link_id='ev'" ":uid='ev'" ":summary='Plan review'" ":location='Room 2'" \
    ":dtstart=NULL" ":dtstart_tzid=NULL" ":dtstart_value=NULL" ":dtend=NULL" ":recurring=NULL" ":until=NULL"
run owner/upsert_task_summary ":collection='Cal'" ":link_id='todo'" ":uid='todo'" ":summary='Send the plan'" ":dtstart=NULL" \
    ":dtstart_tzid=NULL" ":dtstart_value=NULL" ":due=NULL" ":due_tzid=NULL" ":due_value=NULL" ":status=NULL" \
    ":completed=NULL" ":percent=NULL" ":recurring=NULL" ":until=NULL" \
    ":priority=NULL" ":categories='[]'" ":parent=NULL" ":mid=NULL"
run owner/upsert_journal_summary ":collection='Cal'" ":link_id='note'" ":uid='note'" ":summary='Standup'" \
    ":dtstart=NULL" ":dtstart_tzid=NULL" ":dtstart_value=NULL"
run owner/upsert_file_summary ":collection='Docs'" ":link_id='plan'" ":name='plan.pdf'" ":media_type=NULL" ":size=NULL" ":part=NULL"
expect "describe: an endpoint's first live placement and its title, whatever the kind" \
    "$(run read/describe_endpoint ":kind='$mail_kind'" ":link_id='m'")$(run read/describe_endpoint ":kind='$card_kind'" ":link_id='jane'")$(run read/describe_endpoint ":kind='$file_kind'" ":link_id='plan'")|$(run read/describe_endpoint ":kind='$card_kind'" ":link_id='plan'")" \
    "INBOX|1|s mCards|2|Jane DoeDocs|7|plan.pdf|"
sql "UPDATE items SET deleted = 1 WHERE link_id = 'note';"
expect "search: contacts by name or email, A to Z" \
    "$(run read/search_contacts ":collections='[\"Cards\"]'" ":pattern='%plan%'" ":after_key=NULL" ":after_seq=NULL" ":after_collection=NULL" ":limit=10" | cut -d'|' -f3)|$(run read/search_contacts ":collections='[\"Cards\"]'" ":pattern='%o%'" ":after_key='bob'" ":after_seq=3" ":after_collection='Cards'" ":limit=10" | cut -d'|' -f3)" \
    "bob|jane"
expect "search: calendar items by summary or an event's location, live only, naming their component" \
    "$(run read/search_calendar ":collections='[\"Cal\"]'" ":pattern='%plan%'" ":after_key=NULL" ":after_seq=NULL" ":after_collection=NULL" ":limit=10" | cut -d'|' -f3,8 | tr '\n' ' ')|$(run read/search_calendar ":collections='[\"Cal\"]'" ":pattern='%room%'" ":after_key=NULL" ":after_seq=NULL" ":after_collection=NULL" ":limit=10" | cut -d'|' -f3)|$(run read/search_calendar ":collections='[\"Cal\"]'" ":pattern='%standup%'" ":after_key=NULL" ":after_seq=NULL" ":after_collection=NULL" ":limit=10")" \
    "ev|event todo|task |ev|"
expect "search: files by name" \
    "$(run read/search_files ":collections='[\"Docs\"]'" ":pattern='%PLAN%'" ":after_key=NULL" ":after_seq=NULL" ":after_collection=NULL" ":limit=10" | cut -d'|' -f3,8)" "plan|plan.pdf"

# --- A store names the draft that wrote it and opens under no other (§4.2) ---

# opens <format version>: the open every profile runs first (§6 step 2), its
# own format version against the one load_store_meta answers. A store lacking
# the column fails the statement and is refused like any other mismatch.
opens() {
    local meta
    if meta="$(run read/load_store_meta 2>/dev/null)" && [ "$(cut -d'|' -f9 <<< "$meta")" = "$1" ]; then
        echo opened
    else
        echo refused
    fi
}

fresh
expect "format: init_store_meta stamps this draft, version 1 with both compatibility versions, BLAKE3 and the creator's revision" \
    "$(run read/load_store_meta | cut -d'|' -f1,2,3,8,9,10,11)" "pimdir|1|blake3|3|storage-draft-09|1|1"
expect "format: a draft's store opens under that draft alone, never under another nor a release" \
    "$(opens storage-draft-09) $(opens storage-draft-08) $(opens storage-draft-10) $(opens storage-v1)" \
    "opened refused refused refused"
sql "ALTER TABLE store_meta DROP COLUMN format_version;"
expect "format: a store an earlier draft wrote lacks the marker, so load_store_meta fails and it is refused" \
    "$(fails read/load_store_meta && echo failed) $(opens storage-draft-09)" "failed refused"

# --- A migration states what it raises; an added column is harmless (§6) ---

# widths: every reader's and producer's statement with the width of the rows
# it answers, read off its compiled program.
widths() {
    local file
    for file in "$root"/queries/storage/read/*.sql "$root"/queries/storage/queue/*.sql; do
        printf '%s %s\n' "$(basename "$file" .sql)" "$(
            { echo ".explain off"; cat "$root/queries/storage/read/create_param.sql"; echo "EXPLAIN"; cat "$file"; } |
                sqlite3 "$dir/pimdir.db" | awk -F'|' '$2 == "ResultRow" { print $4 }' | sort -u | tr '\n' ' ')"
    done
}

fresh
collection INBOX
widths_before="$(widths)"
# A migration raising neither: an index, a table, and columns a reader may
# ignore on the tables producers write, nullable or with a default.
sql "CREATE INDEX x_items_by_level ON items(level);
     CREATE TABLE x_later (id INTEGER PRIMARY KEY);
     ALTER TABLE queue ADD COLUMN x_note TEXT;
     ALTER TABLE objects ADD COLUMN x_seen INTEGER NOT NULL DEFAULT 0;
     ALTER TABLE collections ADD COLUMN x_icon TEXT;
     ALTER TABLE items ADD COLUMN x_pinned INTEGER NOT NULL DEFAULT 0;"
run owner/set_store_version ":version=2" ":read_version=1" ":produce_version=1"
expect "versions: a migration stamps the three versions it states, the format version following the schema's" \
    "$(run read/load_store_meta | cut -d'|' -f2,9,10,11)" "2|storage-v2|1|1"
expect "versions: a column added beside the others changes the width of no reader's or producer's row" \
    "$(widths)" "$widths_before"
object "$h1"
run queue/pin_object ":hash='$h1'"
run queue/ensure_collection ":collection='Outbox'" ":account=NULL"
run queue/enqueue_action ":producer='p'" ":collection='Outbox'" ":action='submit'" ":payload='{\"v\":1,\"source\":\"smtp\",\"from\":\"alice@example.org\",\"rcpts\":[\"bob@example.org\"]}'" ":object_hash='$h1'"
expect "versions: a producer of the version before writes every row it wrote" \
    "$(sql "SELECT count(*) FROM objects WHERE refcount = 1;")|$(sql "SELECT kind FROM collections WHERE id = 'Outbox';")|$(sql "SELECT action, x_note IS NULL FROM queue;")" \
    "1||submit|1"

# --- A derivation stands at the revision that last wrote it (§6) ------------

fresh
run owner/set_derivation ":derivation=3"
run owner/set_derivation ":derivation=1"
expect "derivation: an owner at an earlier revision records its own, so the next later one re-derives" \
    "$(run read/load_store_meta | cut -d'|' -f8)" "1"
collection INBOX
object "$hb"
mail INBOX held 10 20 "'2026-10-06T08:00:00Z'"
mail INBOX bare 11 21 "'2026-10-06T08:00:00Z'"
sql "UPDATE items SET object_hash = '$hb' WHERE link_id = 'held';"
expect "derivation: list_held_mail pages the rows holding a body" \
    "$(run owner/list_held_mail ":after_collection=NULL" ":after_link_id=NULL" ":limit=10" | cut -d'|' -f2,4)|$(run owner/list_held_mail ":after_collection='INBOX'" ":after_link_id='held'" ":limit=10")" "held|$hb|"
run owner/set_collection_kind ":collection='Cal'" ":account=NULL" ":kind='$cal_kind'"
item Cal tk 12 "'$hb'"
item Cal tn 13
item Cal ev 14 "'$hb'"
sql "INSERT INTO task_summary(item, summary) VALUES ((SELECT id FROM items WHERE collection = 'Cal' AND link_id = 'tk'), 't'), ((SELECT id FROM items WHERE collection = 'Cal' AND link_id = 'tn'), 't');"
expect "derivation: list_held_tasks pages the task rows holding a body, no event, no task without one" \
    "$(run owner/list_held_tasks ":after_collection=NULL" ":after_link_id=NULL" ":limit=10" | cut -d'|' -f2,4)|$(run owner/list_held_tasks ":after_collection='Cal'" ":after_link_id='tk'" ":limit=10")" "tk|$hb|"
for statement in list_held_mail list_held_tasks; do
    expect "derivation: $statement seeks its cursor on the key, the first page's too" \
        "$(plan "owner/$statement" ":after_collection=NULL" ":after_link_id=NULL" ":limit=10" | grep -c '((collection,link_id)>(?,?))' || true)" "1"
done

# --- The store says which sync part wrote its sync state (§14, SYNC.md §10) -

fresh
expect "sync: a store no engine wrote names no sync version, load_store_meta answering it last" \
    "$(run read/load_store_meta | cut -d'|' -f14)|$(run read/load_store_meta | awk -F'|' '{ print NF }')" "|14"
run owner/set_sync_version ":sync_version='sync-draft-08'"
expect "sync: set_sync_version records the engine's version, and nothing else moves" \
    "$(run read/load_store_meta | cut -d'|' -f9,14)" "storage-draft-09|sync-draft-08"
expect "sync: the version is text or nothing" \
    "$(sql "UPDATE store_meta SET sync_version = x'07';" 2>&1 | grep -c CHECK)" "1"

# --- A store is one identity, a restored copy another incarnation (§4.5, §8) -

fresh
first="$(run read/load_change_cursor | cut -d'|' -f3)"
fresh
id="$(run read/load_change_cursor | cut -d'|' -f3)"
expect "identity: a store draws 32 lowercase hex digits at creation, another store others, and starts at incarnation 1" \
    "$(grep -cE '^[0-9a-f]{32}$' <<< "$id")|$([ "$id" != "$first" ] && echo distinct)|$(run read/load_change_cursor | cut -d'|' -f4)" \
    "1|distinct|1"
collection INBOX
item INBOX a 1
sql "VACUUM INTO '$dir/backup.db';"
item INBOX b 2
recorded="$(run read/load_change_cursor)"
# The restore: the copy takes the store's place and is raised past both
# incarnations before anything opens it.
mv "$dir/backup.db" "$dir/pimdir.db"
run owner/raise_incarnation ":replaced=$(cut -d'|' -f4 <<< "$recorded")"
restored="$(run read/load_change_cursor)"
expect "restore: the copy keeps the id, answers another incarnation and a stamp below the one a consumer recorded" \
    "$([ "$(cut -d'|' -f3 <<< "$restored")" = "$id" ] && echo same)|$(cut -d'|' -f4 <<< "$restored")|$([ "$(cut -d'|' -f1 <<< "$restored")" -lt "$(cut -d'|' -f1 <<< "$recorded")" ] && echo below)" \
    "same|2|below"
run owner/raise_incarnation ":replaced=NULL"
expect "restore: with the replaced store unread, the copy's own incarnation is raised" \
    "$(run read/load_change_cursor | cut -d'|' -f4)" "3"
expect "identity: the id never changes and the incarnation never goes down" \
    "$(sql "UPDATE store_meta SET store_id = '00000000000000000000000000000000';" 2>&1 | grep -c 'store identity is fixed')$(sql "UPDATE store_meta SET incarnation = 2;" 2>&1 | grep -c 'store identity is fixed')|$(run read/load_change_cursor | cut -d'|' -f3,4)" \
    "11|$id|3"

# --- Column types are held by the schema (§4.1) -----------------------------

fresh
collection INBOX
expect "types: a value of another type is refused where STRICT refused it, a NULL key and a text checkpoint included" \
    "$(for value in "'$h1', 'big'" "'$h1', 1.5" "CAST('$h1' AS BLOB), 1" "NULL, 1"; do sql "INSERT INTO objects(hash, size) VALUES($value);" 2>&1 | grep -ci error; done | tr -d '\n')$(sql "INSERT INTO sources(collection, source, checkpoint) VALUES('INBOX', 's', 'text');" 2>&1 | grep -ci error)" \
    "11111"
expect "types: a value SQLite converts losslessly is kept, converted" \
    "$(sql "INSERT INTO objects(hash, size) VALUES('$h1', '7'); INSERT INTO items(collection, link_id, seq, level) VALUES('INBOX', 5, 1, 2.0);
            SELECT typeof(size) FROM objects; SELECT typeof(link_id) || typeof(level) FROM items;" | tr '\n' ' ')" "integer textinteger "

# --- Readers count and page under the chips (§14.1) --------------------------

fresh
collection INBOX
collection Sent
mail INBOX a 1 1 "'2026-10-06T08:00:00Z'" '["\\Seen"]'
mail INBOX b 2 2 "'2026-10-06T20:00:00Z'"
mail INBOX c 3 3 "'2026-10-05T08:00:00Z'"
mail Sent a 1 1 "'2026-10-06T08:00:00Z'" '["\\Seen"]'
sql "UPDATE items SET sort_key = (SELECT date FROM mail_summary s WHERE s.item = items.id);
     UPDATE mail_summary SET attachment = 1, subject = 'Invoice 100%' WHERE item IN (SELECT id FROM items WHERE link_id = 'c');
     UPDATE items SET flags_known = 0 WHERE link_id = 'b';"
expect "count: over a set of collections" \
    "$(run read/count_mail ":collections='[\"INBOX\",\"Sent\"]'" ":seen=NULL" ":attachment=NULL")" "4"
expect "count: the read chip, unknown flags unread" \
    "$(run read/count_mail ":collections='[\"INBOX\"]'" ":seen=0" ":attachment=NULL")$(run read/count_mail ":collections='[\"INBOX\"]'" ":seen=1" ":attachment=NULL")" "21"
expect "count: the attachment chip" \
    "$(run read/count_mail ":collections='[\"INBOX\"]'" ":seen=NULL" ":attachment=1")" "1"
expect "count: per day, on the reader's clock, its offset in minutes east and west" \
    "$(run read/count_mail_by_day ":collections='[\"INBOX\"]'" ":seen=NULL" ":attachment=NULL" ":shift=300" | tr '\n' ' ')|$(run read/count_mail_by_day ":collections='[\"INBOX\"]'" ":seen=NULL" ":attachment=NULL" ":shift=-600" | tr '\n' ' ')" \
    "2026-10-07|1 2026-10-06|1 2026-10-05|1 |2026-10-06|1 2026-10-05|1 2026-10-04|1 "
expect "count: unread per collection" \
    "$(run read/count_unread ":collections='[\"INBOX\",\"Sent\"]'" ":attachment=NULL")" "INBOX|2"
expect "page: newest first across collections, one seq in two placed apart" \
    "$(run read/list_mail_page_filtered ":collections='[\"INBOX\",\"Sent\"]'" ":seen=NULL" ":attachment=NULL" \
        ":after_key=NULL" ":after_seq=NULL" ":after_collection=NULL" ":limit=10" | cut -d'|' -f1,2 | tr '\n' ' ')" \
    "INBOX|2 Sent|1 INBOX|1 INBOX|3 "
expect "page: the cursor resumes past the twin" \
    "$(run read/list_mail_page_filtered ":collections='[\"INBOX\",\"Sent\"]'" ":seen=NULL" ":attachment=NULL" \
        ":after_key='2026-10-06T08:00:00Z'" ":after_seq=1" ":after_collection='Sent'" ":limit=10" | cut -d'|' -f1,2 | tr '\n' ' ')" \
    "INBOX|1 INBOX|3 "
expect "search: subject, escaped" \
    "$(run read/search_mail ":collections='[\"INBOX\"]'" ":pattern='%100\\%%'" ":seen=NULL" ":attachment=NULL" \
        ":after_key=NULL" ":after_seq=NULL" ":after_collection=NULL" ":limit=10" | cut -d'|' -f2)" "3"
expect "search: sender, case folded" \
    "$(run read/search_mail ":collections='[\"INBOX\"]'" ":pattern='%ALICE@%'" ":seen=0" ":attachment=NULL" \
        ":after_key=NULL" ":after_seq=NULL" ":after_collection=NULL" ":limit=10" | cut -d'|' -f2 | tr '\n' ' ')" "2 3 "

# An undated row, and sizes known and not, for the floor and the sums.
mail INBOX d 4 4 NULL
sql "UPDATE mail_summary SET size = CASE (SELECT link_id FROM items WHERE id = mail_summary.item) WHEN 'a' THEN 100 WHEN 'c' THEN 50 END WHERE item IN (SELECT id FROM items WHERE collection = 'INBOX');"
inbox=":collections='[\"INBOX\"]'"
both=":collections='[\"INBOX\",\"Sent\"]'"
expect "since: NULL is no floor, the undated row counted" \
    "$(run read/count_mail "$inbox" ":seen=NULL" ":attachment=NULL" ":since=NULL")" "4"
expect "since: a floor leaves out the rows below it and the undated, and keeps a key equal to it" \
    "$(run read/count_mail "$inbox" ":seen=NULL" ":attachment=NULL" ":since='2026-10-06T08:00:00Z'")" "2"
expect "since: per day above the floor, no undated day" \
    "$(run read/count_mail_by_day "$inbox" ":seen=NULL" ":attachment=NULL" ":shift=NULL" ":since='2026-10-06T00:00:00Z'" | tr '\n' ' ')" \
    "2026-10-06|2 "
expect "since: unread above the floor" \
    "$(run read/count_unread "$both" ":attachment=NULL" ":since='2026-10-06T00:00:00Z'")" "INBOX|1"
expect "since: the page ends at the floor" \
    "$(run read/list_mail_page_filtered "$both" ":seen=NULL" ":attachment=NULL" ":since='2026-10-06T00:00:00Z'" \
        ":after_key=NULL" ":after_seq=NULL" ":after_collection=NULL" ":limit=10" | cut -d'|' -f1,2 | tr '\n' ' ')" \
    "INBOX|2 Sent|1 INBOX|1 "
expect "sum: rows, known bytes and unknown sizes above a floor" \
    "$(run read/sum_mail "$inbox" ":seen=NULL" ":attachment=NULL" ":since='2026-10-06T00:00:00Z'" ":until=NULL")" "2|100|1"
expect "sum: a range open below holds the undated" \
    "$(run read/sum_mail "$inbox" ":seen=NULL" ":attachment=NULL" ":since=NULL" ":until='2026-10-06T00:00:00Z'")" "2|50|1"
expect "sum: the range is half-open" \
    "$(run read/sum_mail "$inbox" ":seen=NULL" ":attachment=NULL" ":since='2026-10-05T08:00:00Z'" ":until='2026-10-06T08:00:00Z'")" "1|50|0"
expect "sum: under the chips across collections" \
    "$(run read/sum_mail "$both" ":seen=0" ":attachment=NULL" ":since=NULL" ":until=NULL")$(run read/sum_mail "$both" ":seen=NULL" ":attachment=1" ":since=NULL" ":until=NULL")" \
    "3|50|21|50|0"
expect "sum: nothing in range sums to zero" \
    "$(run read/sum_mail "$both" ":seen=NULL" ":attachment=NULL" ":since='2027-01-01T00:00:00Z'" ":until=NULL")" "0|0|0"
expect "sum: a message filed in two collections counts once, at its largest size" \
    "$(run read/sum_mail "$both" ":seen=NULL" ":attachment=NULL" ":since=NULL" ":until=NULL")" "4|150|2"
object "$hc"
sql "UPDATE items SET object_hash = '$hc', level = 2 WHERE collection = 'INBOX' AND link_id = 'c';"
expect "sum: held 1 is what a release frees, held 0 what a download fetches" \
    "$(run read/sum_mail "$both" ":seen=NULL" ":attachment=NULL" ":held=1" ":since=NULL" ":until=NULL")|$(run read/sum_mail "$both" ":seen=NULL" ":attachment=NULL" ":held=0" ":since=NULL" ":until=NULL")" \
    "1|50|0|3|100|2"
sql "UPDATE items SET object_hash = '$hc', level = 2 WHERE collection = 'Sent' AND link_id = 'a';"
expect "sum: a body one placement holds holds the message" \
    "$(run read/sum_mail "$inbox" ":seen=NULL" ":attachment=NULL" ":held=0" ":since=NULL" ":until=NULL")|$(run read/sum_mail "$both" ":seen=NULL" ":attachment=NULL" ":held=0" ":since=NULL" ":until=NULL")" \
    "3|100|2|2|0|2"
expect "row: one mail row by key, in the page's shape" \
    "$(run read/get_mail_row ":collection='INBOX'" ":link_id='c'" | cut -d'|' -f1,2,3,5,9)" "INBOX|3|c|$hc|Invoice 100%"

# walk <statement> <cursor fields> [:param=literal...]: every page of two,
# each resuming from the last row's cursor, the fields naming it in order
# (key,seq,collection[,role]), the rows' first two columns joined.
walk() {
    local statement="$1" fields="$2" rows last out="" k s c r
    local cursor=(":after_key=NULL" ":after_seq=NULL" ":after_collection=NULL" ":after_role=NULL")
    shift 2
    IFS=, read -r k s c r <<<"$fields"
    while :; do
        rows="$(run "read/$statement" "$@" "${cursor[@]}" ":limit=2" || true)"
        [ -n "$rows" ] || break
        out="$out$(cut -d'|' -f1,2 <<<"$rows" | tr '\n' ' ')"
        [ "$(grep -c . <<<"$rows")" -eq 2 ] || break
        last="$(tail -1 <<<"$rows")"
        cursor=(":after_key='$(cut -d'|' -f"$k" <<<"$last")'" ":after_seq=$(cut -d'|' -f"$s" <<<"$last")"
                ":after_collection='$(cut -d'|' -f"$c" <<<"$last")'" ":after_role=NULL")
        [ -z "$r" ] || cursor[3]=":after_role='$(cut -d'|' -f"$r" <<<"$last")'"
    done
    echo "$out"
}

expect "page: a page smaller than a collection's share merges the set in order, a collection named twice once" \
    "$(walk list_mail_page_filtered 6,2,1 ":collections='[\"INBOX\",\"Sent\",\"INBOX\"]'" ":seen=NULL" ":attachment=NULL" ":since=NULL")" \
    "INBOX|2 Sent|1 INBOX|1 INBOX|3 INBOX|4 "
expect "search: a page smaller than a collection's share merges the set in order" \
    "$(walk search_mail 6,2,1 "$both" ":pattern='%alice%'" ":seen=NULL" ":attachment=NULL")" \
    "INBOX|2 Sent|1 INBOX|1 INBOX|3 INBOX|4 "

# A page over a set of collections is a merge (§9.3): each collection seeks
# items_by_sort below the cursor, the first page's too, and answers at most
# the page, so no page walks the store's order or another kind's rows.
expect "page: no index orders every kind store-wide" \
    "$(sql "SELECT count(*) FROM sqlite_schema WHERE name = 'items_by_sort_global';")" "0"
for statement in list_mail_page_filtered search_mail; do
    steps="$(plan "read/$statement" "$both" ":pattern='%a%'" ":seen=NULL" ":attachment=NULL" ":since=NULL" \
        ":after_key=NULL" ":after_seq=NULL" ":after_collection=NULL" ":limit=10")"
    expect "page: $statement merges each collection's seek below the cursor, scanning nothing" \
        "$(grep -c 'CORRELATED LIST SUBQUERY' <<<"$steps" || true)$(grep -cE 'SEARCH x USING (COVERING )?INDEX items_by_sort \(collection=\? AND .*\(sort_key,seq\)<\(\?,\?\)\)' <<<"$steps" || true)$(grep -c 'SCAN i\b' <<<"$steps" || true)" "110"
done
for statement in list_mail_page_desc list_items_page_desc; do
    expect "page: $statement seeks its cursor on items_by_sort, the first page's too" \
        "$(plan "read/$statement" ":collection='INBOX'" ":after_key=NULL" ":after_seq=NULL" ":limit=10" | grep -c 'items_by_sort (collection=? AND (sort_key,seq)<(?,?))' || true)" "1"
done
for statement in list_items_page_asc list_contacts_page_asc list_events_page_asc list_tasks_page_asc list_journals_page_asc list_files_page_asc; do
    expect "page: $statement seeks its cursor on items_by_sort" \
        "$(plan "read/$statement" ":collection='INBOX'" ":after_key=''" ":after_seq=0" ":limit=10" | grep -c 'items_by_sort (collection=? AND (sort_key,seq)>(?,?))' || true)" "1"
done
for statement in search_contacts search_calendar search_files; do
    steps="$(plan "read/$statement" "$both" ":pattern='%a%'" ":after_key=NULL" ":after_seq=NULL" ":after_collection=NULL" ":limit=10")"
    expect "page: $statement merges each collection's seek above the cursor, scanning nothing" \
        "$(grep -c 'CORRELATED LIST SUBQUERY' <<<"$steps" || true)$(grep -cE 'SEARCH x USING (COVERING )?INDEX items_by_sort \(collection=\? AND \(sort_key,seq\)>\(\?,\?\)\)' <<<"$steps" || true)$(grep -c 'SCAN i\b' <<<"$steps" || true)" "110"
done

expect "since: the page seeks the floor on each collection's items_by_sort" \
    "$(plan read/list_mail_page_filtered "$both" ":since='2026-10-06T00:00:00Z'" | grep -c 'items_by_sort (collection=? AND sort_key>? AND' || true)" "1"
for statement in count_mail count_mail_by_day count_unread; do
    expect "since: $statement seeks the floor on items_by_sort" \
        "$(plan "read/$statement" "$both" ":since='2026-10-06T00:00:00Z'" | grep -c 'items_by_sort (collection=? AND sort_key>?)' || true)" "1"
    expect "count: $statement joins no summary, reading it for the attachment chip alone" \
        "$(plan "read/$statement" "$both" ":seen=NULL" ":attachment=NULL" ":since=NULL" ":shift=NULL" | grep -c 'mail_summary.*LEFT-JOIN' || true)" "0"
done
for statement in count_mail count_mail_by_day count_unread sum_mail list_mail_page_filtered search_mail; do
    expect "count: $statement tests the read flag on the item's bit, seeking no flag row" \
        "$(plan "read/$statement" "$both" ":pattern='%a%'" ":seen=0" ":attachment=NULL" ":since=NULL" ":shift=NULL" \
            ":after_key=NULL" ":after_seq=NULL" ":after_collection=NULL" ":limit=10" | grep -c 'flag=?' || true)" "0"
done
expect "sum: both bounds seek items_by_sort, open or not" \
    "$(plan read/sum_mail "$both" ":since=NULL" ":until=NULL" | grep -c 'items_by_sort (collection=? AND sort_key>? AND sort_key<?)' || true)" "1"

# --- A placement's origin and destination seek one key (§14, SYNC.md §3) ----

fresh
collection INBOX
collection Archive
object "$h1"
mail Archive k 1 10 NULL
sql "UPDATE bindings SET base_object = '$h1' WHERE item IN (SELECT id FROM items WHERE link_id = 'k');"
minted="dup:k#$(printf '\001')k"
sql "INSERT INTO items(collection, link_id, seq, flags_known, level) VALUES('INBOX', '$minted', 2, 1, 2);
     INSERT INTO bindings(item, collection, source, handle) VALUES((SELECT id FROM items WHERE collection = 'INBOX' AND link_id = '$minted'), 'INBOX', 'imap', char(1) || '$minted');"
expect "origin: a create keyed by the key minted over its provisional handle pairs with the key's holder, of the body it intends" \
    "$(run owner/origin_for_link ":link_id='$minted'" ":source='imap'" ":collection='INBOX'" ":object=NULL")|$(run owner/origin_for_link ":link_id='$minted'" ":source='imap'" ":collection='INBOX'" ":object='$h1'")|$(run owner/origin_for_link ":link_id='$minted'" ":source='imap'" ":collection='INBOX'" ":object='$h2'")|$(run owner/origin_for_link ":link_id='$minted'" ":source='graph'" ":collection='INBOX'" ":object=NULL")" \
    "Archive|10|Archive|10||"
expect "destination: a tombstone pairs with the pending create of its key minted elsewhere" \
    "$(run owner/destination_for_link ":link_id='k'" ":source='imap'" ":collection='Archive'" | cut -d'|' -f1)|$(run owner/destination_for_link ":link_id='k'" ":source='imap'" ":collection='INBOX'")" \
    "INBOX|"
for statement in origin_for_link destination_for_link; do
    expect "placement: $statement seeks items_by_link, then the binding's key, never every binding" \
        "$(plan "owner/$statement" ":link_id='$minted'" ":source='imap'" ":collection='INBOX'" ":object=NULL" | grep -cE 'items_by_link \(link_id=\?\)|bindings_1 \(item=\? AND source=\?\)' || true)" "2"
done

# --- A write batch reads its own link ids (§14) ------------------------------

fresh
collection INBOX
run owner/set_collection_kind ":collection='Cal'" ":account=NULL" ":kind='text/calendar'"
mail INBOX a 1 10 NULL
mail INBOX b 2 11 NULL
item Cal t 3
item Cal u 4
sql "INSERT INTO item_address(item, role, position, address) VALUES
         ((SELECT id FROM items WHERE collection = 'INBOX' AND link_id = 'a'), 'from', 0, 'x@example.org'), ((SELECT id FROM items WHERE collection = 'INBOX' AND link_id = 'b'), 'from', 0, 'y@example.org');
     INSERT INTO mail_in_reply_to(item, position, msg_id) VALUES((SELECT id FROM items WHERE collection = 'INBOX' AND link_id = 'a'), 0, 'p'), ((SELECT id FROM items WHERE collection = 'INBOX' AND link_id = 'b'), 0, 'q');
     INSERT INTO task_summary(item, summary) VALUES((SELECT id FROM items WHERE collection = 'Cal' AND link_id = 't'), 't'), ((SELECT id FROM items WHERE collection = 'Cal' AND link_id = 'u'), 'u');
     INSERT INTO task_category(item, position, value) VALUES((SELECT id FROM items WHERE collection = 'Cal' AND link_id = 't'), 0, 'home'), ((SELECT id FROM items WHERE collection = 'Cal' AND link_id = 'u'), 0, 'work');"
expect "batch: a summary, the addresses, the reply ids and the categories load for the slot's link ids alone" \
    "$(run owner/load_mail_summaries_by_link ":collection='INBOX'" ":links='[\"b\"]'" | cut -d'|' -f1)|$(run owner/load_addresses_by_link ":collection='INBOX'" ":links='[\"b\"]'" | cut -d'|' -f1,4)|$(run read/load_in_reply_to_by_link ":collection='INBOX'" ":links='[\"b\"]'")|$(run read/load_categories_by_link ":collection='Cal'" ":links='[\"u\"]'")|$(run owner/load_task_summaries_by_link ":collection='Cal'" ":links='[\"u\"]'" | cut -d'|' -f1,3)" \
    "b|b|y@example.org|b|0|q|u|0|work|u|u"
expect "batch: the same loads over a whole collection" \
    "$(run owner/load_mail_summaries ":collection='INBOX'" | cut -d'|' -f1 | tr '\n' ' ')|$(run owner/load_addresses_by_collection ":collection='INBOX'" | cut -d'|' -f1 | tr '\n' ' ')|$(run read/load_in_reply_to ":collection='INBOX'" | cut -d'|' -f1 | tr '\n' ' ')|$(run read/load_categories ":collection='Cal'" | cut -d'|' -f1 | tr '\n' ' ')" \
    "a b |a b |a b |t u "
for statement in owner/load_mail_summaries_by_link owner/load_contact_summaries_by_link owner/load_event_summaries_by_link \
                 owner/load_task_summaries_by_link owner/load_journal_summaries_by_link owner/load_file_summaries_by_link \
                 owner/load_addresses_by_link read/load_in_reply_to_by_link read/load_categories_by_link; do
    expect "batch: ${statement#*/} seeks each link id, never the collection's rows" \
        "$(plan "$statement" ":collection='INBOX'" ":links='[\"b\"]'" | grep -c '(collection=? AND link_id=?)' || true)" "1"
done

# --- A purge below a cutoff reads what it purges (§11.2) --------------------

fresh
collection INBOX
for hash in "$h1" "$h2" "$h3"; do object "$hash"; done
item INBOX old 1 "'$h1'"
item INBOX twin 2 "'$h1'"
item INBOX new 3 "'$h2'"
item INBOX live 4 "'$h3'"
sql "UPDATE items SET deleted = 1, retained_at = CASE link_id WHEN 'new' THEN '2026-10-01T00:00:00.000Z' ELSE '2026-01-01T00:00:00.000Z' END
     WHERE link_id IN ('old', 'twin', 'new');"
run owner/recompute_refcounts
expect "purge: retained_bytes sums each retained body once" "$(run read/retained_bytes)" "2"
expect "purge: a cutoff takes the rows retired before it, never one retired at it, a later or a live one, answering their pins" \
    "$(run owner/purge_retained_before ":cutoff='2026-10-01T00:00:00.000Z'" | tr '\n' ' ')|$(sql "SELECT group_concat(link_id, ' ') FROM (SELECT link_id FROM items ORDER BY link_id);")" \
    "$h1| $h1| |live new"
for statement in owner/purge_retained_before read/retained_bytes; do
    expect "purge: ${statement#*/} reads items_by_retained, never every item" \
        "$(plan "$statement" ":cutoff='2026-06-01T00:00:00.000Z'" | grep -c 'items_by_retained' || true)$(plan "$statement" ":cutoff='2026-06-01T00:00:00.000Z'" | grep -c 'SCAN items' || true)" "10"
done

# --- Small rows carry no rowid, a pointer index the pointers set (§4.3) -----

fresh
expect "schema: the tables of a few short columns carry no rowid" \
    "$(sql "SELECT group_concat(name, ' ') FROM (SELECT name FROM pragma_table_list WHERE schema = 'main' AND wr = 1 ORDER BY name);")" \
    "binding_base_flag item_address item_reference mail_in_reply_to placement_flag supersessions task_category"
expect "schema: a pointer index holds the set pointers alone, items_by_object too, and items_bodiless the rest, live, which coverage reads" \
    "$(sql "SELECT group_concat(name, ' ') FROM (SELECT name FROM sqlite_schema WHERE type = 'index' AND name GLOB '*_object'
            AND sql GLOB '* IS NOT NULL' ORDER BY name);")|$(sql "SELECT sql FROM sqlite_schema WHERE name = 'items_bodiless';")" \
    "bindings_by_conflict_object bindings_by_object bindings_by_shared_object items_by_conflict_object items_by_object queue_by_object|CREATE INDEX items_bodiless ON items(collection, deleted, object_hash) WHERE object_hash IS NULL AND deleted = 0"
# opens <statement>: the tables and indexes its program reads, foreign keys
# on, by name.
opens() {
    sqlite3 -separator ' ' "$dir/pimdir.db" "PRAGMA foreign_keys = ON; EXPLAIN $1" | awk '$2 == "OpenRead" {print $4}' | sort -u |
        while read -r root; do sql "SELECT name FROM sqlite_schema WHERE rootpage = $root;"; done | sort | tr '\n' ' '
}
expect "schema: an object's delete checks every pointer at it on its index, never reading items, bindings or the queue" \
    "$(opens "DELETE FROM objects WHERE hash = '$h1';")" \
    "bindings_by_conflict_object bindings_by_object bindings_by_shared_object items_by_conflict_object items_by_object queue_by_object "

# --- The person axis pages newest first (§14.1) -----------------------------

fresh
collection INBOX
collection Sent
mail INBOX a 1 10 "'2026-10-01T00:00:00Z'"
mail INBOX b 2 11 "'2026-10-02T00:00:00Z'"
mail Sent b 2 11 "'2026-10-02T00:00:00Z'"
mail INBOX c 3 12 "'2026-10-03T00:00:00Z'"
mail INBOX gone 4 13 "'2026-10-04T00:00:00Z'"
sql "UPDATE items SET sort_key = (SELECT date FROM mail_summary s WHERE s.item = items.id);
     UPDATE items SET deleted = 1 WHERE link_id = 'gone';
     INSERT INTO item_address(item, role, position, address) VALUES
         ((SELECT id FROM items WHERE collection = 'INBOX' AND link_id = 'a'), 'from', 0, 'bob@example.org'), ((SELECT id FROM items WHERE collection = 'INBOX' AND link_id = 'b'), 'to', 0, 'bob@example.org'),
         ((SELECT id FROM items WHERE collection = 'INBOX' AND link_id = 'b'), 'to', 1, 'bob@example.org'), ((SELECT id FROM items WHERE collection = 'INBOX' AND link_id = 'b'), 'cc', 0, 'bob@example.org'),
         ((SELECT id FROM items WHERE collection = 'Sent' AND link_id = 'b'), 'to', 0, 'bob@example.org'), ((SELECT id FROM items WHERE collection = 'INBOX' AND link_id = 'c'), 'from', 0, 'eve@example.org'),
         ((SELECT id FROM items WHERE collection = 'INBOX' AND link_id = 'gone'), 'from', 0, 'bob@example.org');"
expect "people: an address's live placements, newest first, once per role, paged" \
    "$(walk list_address_placements 6,5,2,1 ":address='bob@example.org'" ":role=NULL")|$(walk list_address_placements 6,5,2,1 ":address='bob@example.org'" ":role='to'")" \
    "to|Sent to|INBOX cc|INBOX from|INBOX |to|Sent to|INBOX "
steps="$(plan read/list_address_placements ":address='bob@example.org'" ":role=NULL" ":after_key=NULL" ":after_seq=NULL" ":after_collection=NULL" ":after_role=NULL" ":limit=10")"
expect "people: a page seeks the address on item_address_by_address, holding no more rows than it answers" \
    "$(grep -c 'SEARCH a USING COVERING INDEX item_address_by_address (address=?)' <<<"$steps" || true)$(grep -c 'DISTINCT' <<<"$steps" || true)" "10"

# --- A lookup dedups within an account, never on a derived key (§9, §9.2) --

fresh
collection Work "'work'"
collection Work2 "'work'"
collection Home "'home'"
collection Solo
for hash in "$h1" "$h2" "$h3" "$h4" "$h5"; do object "$hash"; done
item Work 'k@x' 1 "'$h1'"
item Work2 'k@x' 1 "'$h1'"
item Home 'k@x' 1 "'$h2'"
item Solo 'k@x' 1 "'$h3'"
item Work 'alt:s|d|f' 2 "'$h3'"
item Work 'hash:0123456789abcdef' 3 "'$h4'"
item Work 'dup:k@x#7' 4 "'$h5'"
item Work 'meta@x' 5
links=":links='[\"k@x\",\"alt:s|d|f\",\"hash:0123456789abcdef\",\"dup:k@x#7\",\"meta@x\"]'"
expect "lookup: an account's body for a stated key, with its size, never another account's, a derived or a minted key's, nor a bodiless row's" \
    "$(run owner/lookup_objects ":account='work'" "$links" | sort -u | tr '\n' ' ')|$(run owner/lookup_objects ":account='home'" "$links" | tr '\n' ' ')|$(run owner/lookup_objects ":account=NULL" "$links" | tr '\n' ' ')" \
    "k@x|$h1|1 |k@x|$h2|1 |k@x|$h3|1 "
# summary <collection> <link_id> <attachment> <invitation>: a mail summary
# stating the two columns a body gives.
summary() {
    run owner/upsert_mail_summary ":collection='$1'" ":link_id='$2'" ":message_id=NULL" ":subject=''" \
        ":sender=NULL" ":sender_name=NULL" ":date=NULL" ":size=1" ":attachment=$3" ":invitation=$4"
}
summary Work 'k@x' NULL NULL
summary Work2 'k@x' 1 "'ev@x'"
summary Home 'k@x' 0 NULL
summary Work 'alt:s|d|f' 1 "'alt@x'"
sql "UPDATE items SET object_hash = '$h1' WHERE link_id = 'alt:s|d|f';"
expect "held: a body's columns come from a row of the account holding it, one stating its mark first, never another account's nor a derived key's" \
    "$(run owner/held_mail_summary ":account='work'" ":link_id='k@x'" ":object='$h1'")|$(run owner/held_mail_summary ":account='home'" ":link_id='k@x'" ":object='$h1'")|$(run owner/held_mail_summary ":account='home'" ":link_id='k@x'" ":object='$h2'")|$(run owner/held_mail_summary ":account='work'" ":link_id='alt:s|d|f'" ":object='$h1'")" \
    "1|ev@x||0||"

# --- A handle binds one item; a retained row revives under its seq (§9.1, §11)

fresh
collection INBOX
collection Archive
object "$h1"
item INBOX a 7 "'$h1'"
item INBOX b 8
item INBOX c 9
item Archive a 7 "'$h1'"
bind INBOX a imap 10 1
bind INBOX a graph g1 1
bind INBOX b imap 11 1
expect "handle: link_for_handle and handle_for_link answer each other, per source" \
    "$(run owner/link_for_handle ":collection='INBOX'" ":source='imap'" ":handle='10'")|$(run read/handle_for_link ":collection='INBOX'" ":link_id='a'" ":source='graph'")|$(run owner/link_for_handle ":collection='INBOX'" ":source='graph'" ":handle='10'")" \
    "a|g1|"
expect "handle: a source binds a handle once in a collection, bindings_by_handle refusing a second item under it, another source's or collection's taking it" \
    "$(bind INBOX c imap 10 1 2>&1 | grep -c 'UNIQUE constraint failed: bindings.collection, bindings.source, bindings.handle')|$(bind INBOX c graph 10 1 2>&1)|$(bind Archive a imap 10 1 2>&1)|$(sql "SELECT count(*) FROM bindings;")" \
    "1|||5"
run owner/delete_binding ":collection='INBOX'" ":link_id='a'" ":source='graph'"
expect "binding: delete_binding drops one source's binding, the item and its other bindings kept" \
    "$(sql "SELECT group_concat(source || ':' || handle, ' ') FROM (SELECT source, handle FROM bindings WHERE collection = 'INBOX' AND item IN (SELECT id FROM items WHERE link_id = 'a') ORDER BY source);")|$(sql "SELECT count(*) FROM items WHERE link_id = 'a';")|$(sql "SELECT count(*) FROM bindings;")" \
    "imap:10|2|4"
for link in a c; do
    run owner/delete_item_bindings ":collection='INBOX'" ":link_id='$link'"
    run owner/retain_item ":collection='INBOX'" ":link_id='$link'" ":source='imap'"
done
expect "retained: retained_item answers a retained row's seq and its pins, a live row nothing" \
    "$(run owner/retained_item ":collection='INBOX'" ":link_id='a'")|$(run owner/retained_item ":collection='INBOX'" ":link_id='b'")" "7|$h1||"
run owner/revive_item ":collection='INBOX'" ":link_id='a'"
expect "revive: the row is live again under its seq and body, retired by no source, the other retained row and the other collection's untouched" \
    "$(sql "SELECT seq, object_hash, deleted, retained_at IS NULL, retained_by IS NULL FROM items WHERE collection = 'INBOX' AND link_id = 'a';")|$(run read/count_retained ":collection='INBOX'")|$(run owner/retained_item ":collection='INBOX'" ":link_id='a'")|$(sql "SELECT deleted FROM items WHERE collection = 'Archive';")" \
    "7|$h1|0|1|1|1||0"

# --- A refcount never falls below zero (§5, §7) -----------------------------

fresh
collection INBOX
object "$h1"
run queue/pin_object ":hash='$h1'"
run owner/release_pins ":hashes='[\"$h1\"]'"
expect "refcount: a release past the pins taken is refused by the statement making it, the count kept" \
    "$(run owner/release_pins ":hashes='[\"$h1\"]'" 2>&1 | grep -c 'CHECK constraint failed: refcount >= 0')|$(sql "SELECT refcount FROM objects;")" "1|0"
run queue/pin_object ":hash='$h1'"
expect "refcount: a pin named twice in one release is released twice, so a second is refused whole" \
    "$(run owner/release_pins ":hashes='[\"$h1\",\"$h1\"]'" 2>&1 | grep -c 'CHECK constraint failed: refcount >= 0')|$(sql "SELECT refcount FROM objects;")|$(run owner/adjust_refcount ":hash='$h1'" ":delta=-2" 2>&1 | grep -c 'CHECK constraint failed')" \
    "1|1|1"

# --- A keyset page walks every row once, its cursor a pair (§9.3) ----------

# pages <statement> <key> <seq> [:param=literal...]: every page of two of a
# keyset read over one collection, the first from the cursor given, each next
# one from the last row's sort key (its fifth column) and seq (its first), the
# seqs joined; twenty pages at most, so a cursor that fails to advance fails
# the scenario rather than loops.
pages() {
    local statement="$1" key="$2" seq="$3" rows last out="" n=0
    shift 3
    while [ "$n" -lt 20 ]; do
        rows="$(run "read/$statement" "$@" ":after_key=$key" ":after_seq=$seq" ":limit=2" || true)"
        [ -n "$rows" ] || break
        out="$out$(cut -d'|' -f1 <<<"$rows" | tr '\n' ' ')"
        [ "$(grep -c . <<<"$rows")" -eq 2 ] || break
        last="$(tail -1 <<<"$rows")"
        key="'$(cut -d'|' -f5 <<<"$last")'"
        seq="$(cut -d'|' -f1 <<<"$last")"
        n=$((n + 1))
    done
    echo "$out"
}

fresh
collection C
for spec in a:1:k2 b:2:k1 c:3:k1 d:4:k1 e:5:k3 f:6:k1; do
    IFS=: read -r link seq key <<<"$spec"
    item C "$link" "$seq"
    run owner/set_sort_key ":collection='C'" ":link_id='$link'" ":sort_key='$key'"
done
sql "UPDATE items SET deleted = 1 WHERE link_id = 'f';"
run owner/upsert_contact_summary ":collection='C'" ":link_id='b'" ":uid='b'" ":fn='Bob'" ":kind=NULL" ":org=NULL"
expect "sort key: set_sort_key restates the key of the item it names alone" \
    "$(sql "SELECT group_concat(link_id || '=' || sort_key, ' ') FROM (SELECT link_id, sort_key FROM items ORDER BY link_id);")" \
    "a=k2 b=k1 c=k1 d=k1 e=k3 f=k1"
expect "page: ascending, a tie broken by seq, the cursor's row never twice, a tombstone never" \
    "$(pages list_items_page_asc "''" 0 ":collection='C'")" "2 3 4 1 5 "
expect "page: descending from a NULL cursor, the same rows reversed, for any item and for mail" \
    "$(pages list_items_page_desc NULL NULL ":collection='C'")|$(pages list_mail_page_desc NULL NULL ":collection='C'")" \
    "5 1 4 3 2 |5 1 4 3 2 "
for statement in list_contacts_page_asc list_events_page_asc list_tasks_page_asc list_journals_page_asc list_files_page_asc; do
    expect "page: $statement walks the same order, an item with no summary row listed" \
        "$(pages "$statement" "''" 0 ":collection='C'")" "2 3 4 1 5 "
done
expect "page: a kind's page joins its summary" \
    "$(run read/list_contacts_page_asc ":collection='C'" ":after_key=''" ":after_seq=0" ":limit=1" | cut -d'|' -f1,8)" "2|Bob"
expect "page: in link-id order from the empty string for a sweep, a tombstone never" \
    "$(run read/list_items_page ":collection='C'" ":after=''" ":limit=3" | cut -d'|' -f2 | tr '\n' ' ')|$(run read/list_items_page ":collection='C'" ":after='c'" ":limit=3" | cut -d'|' -f2 | tr '\n' ' ')" \
    "a b c |d e "
expect "count: count_items counts the live items alone" "$(run read/count_items ":collection='C'")" "5"

# --- A load reads the live rows, a get one live item (§14, §14.1) ----------

fresh
collection INBOX
for spec in Cards:text/vcard Cal:text/calendar Files:application/octet-stream; do
    run owner/set_collection_kind ":collection='${spec%%:*}'" ":account=NULL" ":kind='${spec#*:}'"
done
object "$h1"
item INBOX a 1 "'$h1'"
item INBOX b 2
item INBOX gone 3
run owner/retain_item ":collection='INBOX'" ":link_id='gone'" ":source='imap'"
bind INBOX a imap 10 1
bind INBOX b imap 11 0
expect "load: the live items, their flags and body, a retained row never, the slot narrowing them" \
    "$(run owner/load_items ":collection='INBOX'" | cut -d'|' -f1-3 | sort | tr '\n' ' ')|$(run owner/load_items_by_link ":collection='INBOX'" ":links='[\"b\",\"gone\"]'" | cut -d'|' -f1)" \
    "a||$h1 b|| |b"
expect "load: the bindings with their base, a base's flags known or unknown, the slot narrowing them" \
    "$(run owner/load_bindings ":collection='INBOX'" ".nullvalue=NULL" | cut -d'|' -f1-4,7 | sort | tr '\n' ' ')|$(run owner/load_bindings_by_link ":collection='INBOX'" ":links='[\"b\"]'" | cut -d'|' -f1)" \
    "a|imap|10||1 b|imap|11|NULL|0 |b"
item Cards c 1
item Cards d 2
item Cal e 1
item Cal t 2
item Cal j 3
item Files f 1
run owner/upsert_contact_summary ":collection='Cards'" ":link_id='c'" ":uid='c'" ":fn='Carol'" ":kind='individual'" ":org='ACME'"
run owner/upsert_event_summary ":collection='Cal'" ":link_id='e'" ":uid='e'" ":summary='Review'" ":location='Room 1'" \
    ":dtstart='20261001T100000'" ":dtstart_tzid='Europe/Paris'" ":dtstart_value=NULL" ":dtend='20261001T110000'" ":recurring=0" ":until=NULL"
run owner/upsert_task_summary ":collection='Cal'" ":link_id='t'" ":uid='t'" ":summary='Pay'" ":dtstart=NULL" ":dtstart_tzid=NULL" \
    ":dtstart_value=NULL" ":due='20261002'" ":due_tzid=NULL" ":due_value='DATE'" ":status='NEEDS-ACTION'" ":completed=NULL" \
    ":percent=NULL" ":recurring=0" ":until=NULL" ":priority=NULL" ":parent=NULL" ":mid=NULL" ":created=NULL"
run owner/upsert_journal_summary ":collection='Cal'" ":link_id='j'" ":uid='j'" ":summary='Notes'" ":dtstart='20261003'" \
    ":dtstart_tzid=NULL" ":dtstart_value='DATE'"
run owner/upsert_file_summary ":collection='Files'" ":link_id='f'" ":name='a.pdf'" ":media_type='application/pdf'" ":size=3" ":part=NULL"
expect "load: each kind's summaries over a collection, and over the slot's link ids, another kind's never" \
    "$(run owner/load_contact_summaries ":collection='Cards'")|$(run owner/load_contact_summaries_by_link ":collection='Cards'" ":links='[\"d\"]'")|$(run owner/load_event_summaries ":collection='Cal'" | cut -d'|' -f1,3,4,8)|$(run owner/load_event_summaries_by_link ":collection='Cal'" ":links='[\"e\",\"t\"]'" | cut -d'|' -f1)|$(run owner/load_task_summaries ":collection='Cal'" | cut -d'|' -f1,7,10)|$(run owner/load_journal_summaries ":collection='Cal'" | cut -d'|' -f1,3)|$(run owner/load_journal_summaries_by_link ":collection='Cal'" ":links='[\"t\",\"j\"]'" | cut -d'|' -f1)|$(run owner/load_file_summaries ":collection='Files'")|$(run owner/load_file_summaries_by_link ":collection='Files'" ":links='[\"f\"]'" | cut -d'|' -f2)" \
    "c|c|Carol|individual|ACME||e|Review|Room 1|20261001T110000|e|t|20261002|NEEDS-ACTION|j|Notes|j|f|a.pdf|application/pdf|3||a.pdf"
expect "get: one live item by seq with its kind's summary, an item with no summary row too, a tombstone never" \
    "$(run read/get_contact ":collection='Cards'" ":seq=1" | cut -d'|' -f1,2,8)|$(run read/get_contact ":collection='Cards'" ":seq=2" | cut -d'|' -f1,2,8)|$(run read/get_event ":collection='Cal'" ":seq=1" | cut -d'|' -f2,8)|$(run read/get_task ":collection='Cal'" ":seq=2" | cut -d'|' -f2,15)|$(run read/get_journal ":collection='Cal'" ":seq=3" | cut -d'|' -f2,11)|$(run read/get_mail ":collection='INBOX'" ":seq=1" | cut -d'|' -f2,4)|$(run read/get_mail ":collection='INBOX'" ":seq=3")" \
    "1|c|Carol|2|d||e|Review|t|NEEDS-ACTION|j|DATE|a|$h1|"
expect "component: the calendar table holding an item, none for another kind" \
    "$(for link in e t j; do run read/component_of ":collection='Cal'" ":link_id='$link'"; done | tr '\n' ' ')|$(run read/component_of ":collection='Cards'" ":link_id='c'")" \
    "VEVENT VTODO VJOURNAL |"
for kind in event task journal; do
    run "owner/delete_${kind}_summary" ":collection='Cal'" ":link_id='${kind:0:1}'"
done
expect "delete: a calendar summary goes alone, the item still read, through no table" \
    "$(sql "SELECT count(*) FROM event_summary; SELECT count(*) FROM task_summary; SELECT count(*) FROM journal_summary; SELECT count(*) FROM items WHERE collection = 'Cal';" | tr '\n' ' ')|$(run read/component_of ":collection='Cal'" ":link_id='e'")|$(run read/get_event ":collection='Cal'" ":seq=1" | cut -d'|' -f2,8)" \
    "0 0 0 3 ||e|"

# --- A derivation replaces a set whole (§14, Annex A) ----------------------

fresh
collection INBOX
run owner/set_collection_kind ":collection='Cal'" ":account=NULL" ":kind='text/calendar'"
item INBOX m 1
item INBOX n 2
item Cal t 3
item Cal u 4
summary INBOX m 0 NULL
summary INBOX n 0 NULL
for spec in m:to:1:b@x m:to:0:a@x m:from:0:f@x n:to:0:z@x; do
    IFS=: read -r link role position address <<<"$spec"
    run owner/insert_address ":collection='INBOX'" ":link_id='$link'" ":role='$role'" ":position=$position" \
        ":address='$address'" ":name=$([ "$role" = from ] && echo "'F'" || echo NULL)"
done
expect "addresses: one item's people in document order within each role" \
    "$(run read/load_addresses ":collection='INBOX'" ":link_id='m'" | tr '\n' ' ')" "from|0|f@x|F to|0|a@x| to|1|b@x| "
run owner/replace_addresses ":collection='INBOX'" ":link_id='m'"
run owner/insert_address ":collection='INBOX'" ":link_id='m'" ":role='to'" ":position=0" ":address='c@x'" ":name=NULL"
for spec in m:0:p@x m:1:q@x n:0:r@x; do
    IFS=: read -r link position id <<<"$spec"
    run owner/insert_in_reply_to ":collection='INBOX'" ":link_id='$link'" ":position=$position" ":msg_id='$id'"
done
run owner/replace_in_reply_to ":collection='INBOX'" ":link_id='m'"
run owner/insert_in_reply_to ":collection='INBOX'" ":link_id='m'" ":position=0" ":msg_id='s@x'"
for link in t u; do
    run owner/upsert_task_summary ":collection='Cal'" ":link_id='$link'" ":uid='$link'" ":summary='$link'" ":dtstart=NULL" \
        ":dtstart_tzid=NULL" ":dtstart_value=NULL" ":due=NULL" ":due_tzid=NULL" ":due_value=NULL" ":status=NULL" \
        ":completed=NULL" ":percent=NULL" ":recurring=0" ":until=NULL" ":priority=NULL" ":parent=NULL" ":mid=NULL" ":created=NULL"
done
for spec in t:0:home t:1:work u:0:errand; do
    IFS=: read -r link position value <<<"$spec"
    run owner/insert_category ":collection='Cal'" ":link_id='$link'" ":position=$position" ":value='$value'"
done
run owner/replace_categories ":collection='Cal'" ":link_id='t'"
run owner/insert_category ":collection='Cal'" ":link_id='t'" ":position=0" ":value='later'"
expect "replace: the addresses, the reply ids and the categories of one item are replaced whole, another item's kept" \
    "$(run read/load_addresses ":collection='INBOX'" ":link_id='m'" | tr '\n' ' ')|$(run read/load_addresses ":collection='INBOX'" ":link_id='n'" | cut -d'|' -f3)|$(run read/load_in_reply_to ":collection='INBOX'" | tr '\n' ' ')|$(run read/load_categories ":collection='Cal'" | tr '\n' ' ')" \
    "to|0|c@x| |z@x|m|0|s@x n|0|r@x |t|0|later u|0|errand "

# --- A collection's account, kind, epoch and policy; the next seq (§9.1, §14)

fresh
collection INBOX "'work'"
collection Archive "'work'"
collection Notes "'home'"
collection Solo
sql "INSERT INTO collections(id, kind, name) VALUES('Lazy', '', 'Lazy');"
expect "account: the accounts a store knows through its collections, sorted, a single-account collection naming none" \
    "$(run read/list_accounts | tr '\n' ' ')|$(run read/load_account ":collection='Notes'")|$(run read/load_account ":collection='Solo'")" "home work |home|"
run owner/set_collection_account ":collection='Notes'" ":account='work'"
expect "account: set_collection_account moves the collection it names alone" \
    "$(run read/list_accounts | tr '\n' ' ')|$(run read/load_account ":collection='Notes'")|$(run read/load_account ":collection='INBOX'")" "work |work|work"
expect "kind: a collection a sync created reads '' until declared" \
    "$(run read/load_kind ":collection='Lazy'")|$(run read/load_kind ":collection='INBOX'")" "|message/rfc822"
expect "generation: a rebuild bumps the epoch it answers, every other collection's left" \
    "$(run owner/bump_generation ":collection='INBOX'")|$(run read/load_generation ":collection='INBOX'")|$(run read/load_generation ":collection='Archive'")" "2|2|1"
expect "conflict: a policy reads manual until set, then what was set; a value outside the vocabulary is refused" \
    "$(run owner/load_conflict ":collection='INBOX'")|$(run owner/set_conflict ":collection='INBOX'" ":conflict='prefer-incoming'"; run owner/load_conflict ":collection='INBOX'")|$(run owner/set_conflict ":collection='INBOX'" ":conflict='prefer-remote'" 2>&1 | grep -c 'CHECK constraint failed')|$(run owner/load_conflict ":collection='INBOX'")|$(run owner/load_conflict ":collection='Archive'")" \
    "manual|prefer-incoming|1|prefer-incoming|manual"
next="$(sql "SELECT next_seq FROM store_meta;")"
expect "seq: bump_next_seq answers the next seq once, drawing it" \
    "$(run owner/bump_next_seq)|$(run owner/bump_next_seq)|$(sql "SELECT next_seq FROM store_meta;")" "$next|$((next + 1))|$((next + 2))"

# --- A failed action is retried; a parked one is listed apart (§15.2, §15.4)

fresh
collection INBOX
collection Archive
run queue/enqueue_action ":producer='p'" ":collection='INBOX'" ":action='set-flags'" ":payload='{\"v\":1,\"seq\":1,\"flags\":[\"\\\\Seen\"]}'" ":object_hash=NULL"
run queue/enqueue_action ":producer='p'" ":collection='Archive'" ":action='remove'" ":payload='{\"v\":1,\"seq\":2}'" ":object_hash=NULL"
run queue/enqueue_action ":producer='p'" ":collection='INBOX'" ":action='remove'" ":payload='{\"v\":1,\"seq\":3}'" ":object_hash=NULL"
run owner/bump_attempts ":id=1"
run owner/bump_attempts ":id=1"
run owner/park_action ":id=3" ":error='unknown seq: 3'"
expect "attempts: a retried row counts its attempts and stays pending in its collection" \
    "$(run read/load_pending_actions ":collection='INBOX'" | cut -d'|' -f1,4,8 | tr '\n' ' ')|$(run read/load_pending_actions ":collection='Archive'" | cut -d'|' -f1,8)" \
    "1|set-flags|2 |2|0"
expect "parked: a parked row is listed store-wide with its error, never as pending" \
    "$(run owner/load_parked_actions | cut -d'|' -f1,4,5,9 | tr '\n' ' ')" "3|INBOX|remove|unknown seq: 3 "

# --- Placements by key, body and domain; what waits on a decision (§14.1) --

fresh
collection INBOX "'work'"
collection Archive "'work'"
collection Home "'home'"
collection Solo
for hash in "$h1" "$h2" "$h3"; do object "$hash"; done
item INBOX 'k@x' 1 "'$h1'"
item Archive 'k@x' 1 "'$h1'"
item Archive 'dup:k@x#9' 2 "'$h1'"
item Home 'k@x' 1 "'$h2'"
item Solo 'k@x' 1 "'$h1'"
item INBOX 'gone@x' 2
run owner/retain_item ":collection='Archive'" ":link_id='k@x'" ":source='imap'"
sql "UPDATE items SET deleted = 1 WHERE link_id = 'gone@x';
     UPDATE items SET sort_key = CASE collection WHEN 'INBOX' THEN '2026-10-02' ELSE '2026-10-01' END;"
expect "placements: a key's live placements, by account then collection, a single-account one last, a minted or retained one never" \
    "$(run read/list_link_placements ":link_id='k@x'" | cut -d'|' -f1-4 | tr '\n' ' ')" \
    "Home|home|1|$h2 INBOX|work|1|$h1 Solo||1|$h1 "
expect "placements: a body's live placements, whatever their keys, in the same order, a retained one never" \
    "$(run read/list_object_placements ":hash='$h1'" | cut -d'|' -f1,2,4 | tr '\n' ' ')" \
    "Archive|work|dup:k@x#9 INBOX|work|k@x Solo||k@x "
for spec in INBOX:k@x:from:bob@example.org INBOX:k@x:to:eve@sub.example.org INBOX:k@x:cc:x@notexample.org \
            Home:k@x:to:amy@example.org Archive:k@x:from:old@example.org INBOX:gone@x:from:gone@example.org; do
    IFS=: read -r collection link role address <<<"$spec"
    run owner/insert_address ":collection='$collection'" ":link_id='$link'" ":role='$role'" ":position=0" \
        ":address='$address'" ":name=NULL"
done
expect "domain: the live placements naming an address of the domain itself, newest first, under a role or any" \
    "$(run read/list_domain_placements ":domain='example.org'" ":role=NULL" | cut -d'|' -f1-3 | tr '\n' ' ')|$(run read/list_domain_placements ":domain='example.org'" ":role='to'" | cut -d'|' -f1)" \
    "bob@example.org|from|INBOX amy@example.org|to|Home |amy@example.org"
bind INBOX k@x imap 10 1
bind Home k@x imap 10 1
bind Solo k@x graph g1 1
sql "UPDATE bindings SET conflicted = 1, conflict_revision = 'r2', conflict_object = '$h3' WHERE collection = 'INBOX';
     UPDATE bindings SET conflicted = 1 WHERE collection = 'Home';
     UPDATE items SET conflicted = 1, conflict_object = '$h3' WHERE collection = 'INBOX' AND link_id = 'k@x';"
expect "conflicts: an account's conflicted bindings with base, local and remote, its conflicted items with both bodies, another account's apart" \
    "$(run read/list_conflicted_bindings ":account='work'" | tr '\n' ' ')|$(run read/list_conflicted_items ":account='work'" | tr '\n' ' ')|$(run read/list_conflicted_bindings ":account='home'" | cut -d'|' -f1)|$(run read/list_conflicted_items ":account='home'")" \
    "INBOX|k@x|imap|10|r2||$h1|$h3 |INBOX|k@x|1|$h1|$h3 |Home|"
expect "sources: every source holding a binding, once, sorted" "$(run read/list_sources | tr '\n' ' ')" "graph imap "
expect "collector: object_exists answers a stored name, nothing for another" \
    "$(run owner/object_exists ":hash='$h1'")|$(run owner/object_exists ":hash='$h4'")" "1|"

# --- A list parameter is its slot's rows, bound one at a time (§4.4) ------

fresh
collection INBOX
for spec in a:1 b:2 c:3; do item INBOX "${spec%:*}" "${spec#*:}"; done
expect "param: bind_param fills a slot a value at a time, a value bound twice kept twice, and clear_param empties every slot" \
    "$( {
        prelude
        statement storage/read/create_param
        echo ".parameter set :collection 'INBOX'"
        position=0
        for value in c a c; do
            echo ".parameter set :slot 'links'"
            echo ".parameter set :position $position"
            echo ".parameter set :value '$value'"
            statement storage/read/bind_param
            position=$((position + 1))
        done
        echo "SELECT count(*) FROM temp.param;"
        statement storage/owner/load_items_by_link
        statement storage/read/clear_param
        echo "SELECT count(*) FROM temp.param;"
    } | sqlite3 "$dir/pimdir.db" | cut -d'|' -f1 | tr '\n' ' ')" \
    "3 a c 0 "

# --- The search index (SEARCH.md) --------------------------------------------

# index: an empty index.db at the canonical search schema.
index() {
    for migration in "$root"/migrations/search/*.sql; do
        sqlite3 "$dir/index.db" "BEGIN; $(cat "$migration")"$'\n'"PRAGMA user_version = 1; COMMIT;"
    done
}

# isearch <name> [:param=literal...]: one statement of queries/search, bound
# as run binds a store statement, a list through its slot (STORAGE.md §4.4),
# on index.db with the store attached as `store` (SEARCH.md §3).
isearch() {
    local file="$1"; shift
    {
        prelude
        echo "PRAGMA foreign_keys = ON;"
        echo "ATTACH '$dir/pimdir.db' AS store;"
        bindings "$@"
        statement "search/$file"
    } | sqlite3 "$dir/index.db"
}

# isplan <name> [:param=literal...]: its query plan, bound.
isplan() {
    local file="$1"; shift
    {
        echo "ATTACH '$dir/pimdir.db' AS store;"
        bindings "$@"
        echo "EXPLAIN QUERY PLAN"
        cat "$root/queries/search/$file.sql"
    } | sqlite3 "$dir/index.db"
}

# body <hash> [:attachment=1] ...: an object row, answering its id.
body() {
    local hash="$1"; shift
    isearch insert_object ":hash='$hash'" ":status='ok'" ":attachment=0" ":tel=0" ":adr=0" ":bday=0" ":photo=0" "$@"
}

# text <rowid> <title> <body>: a body's text, every other field empty.
text() {
    isearch insert_object_text ":rowid=$1" ":title='$2'" ":body='$3'" ":people=''" ":attachment=''" ":place=''" \
        ":org=''" ":note=''" ":from=''" ":to=''" ":cc=''" ":bcc=''" ":email=''" ":organizer=''" ":attendee=''"
}

for label in ha hn ct cf; do
    printf -v "$label" '%s' "$(name "$label")"
done

fresh
index
expect "index: an object and a placement name a body as the store does, 52 characters of a-z2-7, never a path" \
    "$(for hash in ../x "${h1^^}" "${h1:0:26}"; do body "$hash" 2>&1 | grep -c 'CHECK constraint failed'; done | tr -d '\n')|$(isearch upsert_placement ":collection='C'" ":seq=1" ":link_id='x'" ":hash='../x'" 2>&1 | grep -c 'CHECK constraint failed')|$(body "$h1")" \
    "111|1|1"
object_id="$(sqlite3 "$dir/index.db" "SELECT id FROM object WHERE hash = '$h1';")"
isearch insert_chunk ":object=$object_id" ":ord=1" ":field='note'" ":start=0" ":end=4"
isearch insert_chunk ":object=$object_id" ":ord=0" ":field='body'" ":start=0" ":end=10"
expect "chunk: a body's chunks list in text order across fields" \
    "$(isearch chunks_of ":hash='$h1'" | tr '\n' ' ')" "0|body|0|10 1|note|0|4 "
isearch delete_object ":rowid=$object_id"
isearch delete_object_row ":hash='$h1'"
expect "chunk: the chunks go with their object" \
    "$(sqlite3 "$dir/index.db" "SELECT count(*) FROM chunk;")" "0"

fresh
index
run owner/set_collection_kind ":collection='Cal'" ":account=NULL" ":kind='text/calendar'"
item Cal ev 1
sql "UPDATE items SET sort_key = '2026-09-01T10:00:00Z' WHERE link_id = 'ev';"
run owner/upsert_event_summary ":collection='Cal'" ":link_id='ev'" ":uid='ev'" ":summary='Review'" ":location=NULL" \
    ":dtstart='20260901T120000'" ":dtstart_tzid='Europe/Paris'" ":dtstart_value=NULL" ":dtend=NULL" ":recurring=0" ":until=NULL"
isearch init_index_meta ":version=1" ":tokenizer='unicode61 remove_diacritics 0'"
isearch set_horizon ":horizon_start='2025-08-20T12:00:00Z'" ":horizon_end='2028-08-20T12:00:00Z'"
isearch set_tzdb_version ":tzdb_version='2026a'"
window=(":old_start='2025-08-20T12:00:00Z'" ":old_end='2028-08-20T12:00:00Z'"
        ":new_start='2025-08-20T12:00:00Z'" ":new_end='2028-08-20T12:00:00Z'")
expect "tzdb: the version the occurrences stand under re-expands nothing" \
    "$(isearch items_to_reexpand "${window[@]}" ":tzdb_version='2026a'" ":floating_zone='UTC'")" ""
expect "tzdb: another version re-expands a single zoned event inside the horizon" \
    "$(isearch items_to_reexpand "${window[@]}" ":tzdb_version='2026b'" ":floating_zone='UTC'")" "Cal|1"

# --- Floating times are read in the zone the index records (SEARCH.md §7) ---

expect "zone: an index reads floating times in UTC until an indexer states another" \
    "$(isearch load_index_meta | cut -d'|' -f12)" "UTC"
expect "zone: an indexer stating another zone re-expands every live calendar item, a single one inside the horizon included" \
    "$(isearch items_to_reexpand "${window[@]}" ":tzdb_version='2026a'" ":floating_zone='Europe/Paris'")" "Cal|1"
isearch set_floating_zone ":floating_zone='Europe/Paris'"
expect "zone: once recorded, the zone re-expands nothing more, and UTC is another zone again" \
    "$(isearch load_index_meta | cut -d'|' -f12)|$(isearch items_to_reexpand "${window[@]}" ":tzdb_version='2026a'" ":floating_zone='Europe/Paris'")|$(isearch items_to_reexpand "${window[@]}" ":tzdb_version='2026a'" ":floating_zone='UTC'")" \
    "Europe/Paris||Cal|1"

# --- Coverage counts the query's collections (SEARCH.md §8.2) ---------------

run owner/set_collection_kind ":collection='Docs'" ":account=NULL" ":kind='application/octet-stream'"
item Docs plan 2
run owner/set_collection_kind ":collection='Cal2'" ":account=NULL" ":kind='text/calendar'"
item Cal2 other 3
expect "coverage: a bodiless file hides nothing from search and is never counted" \
    "$(isearch coverage ":collections='[\"Cal\",\"Docs\"]'")" "text/calendar|1"
expect "coverage: only the query's collections are counted" \
    "$(isearch coverage ":collections='[\"Docs\"]'")|$(isearch coverage ":collections='[\"Cal\",\"Cal2\"]'")" "|text/calendar|2"
steps="$(isplan coverage ":collections='[\"Cal\"]'")"
expect "coverage: each collection seeks items_bodiless, never the store's other rows" \
    "$(grep -c 'USING COVERING INDEX items_bodiless (collection=? AND deleted=? AND object_hash=?)' <<<"$steps" || true)$(grep -c 'items_by_object\|SCAN i' <<<"$steps" || true)" "10"

# --- A zero-length occurrence falls in the range it starts (SEARCH.md §8.1) --

isearch upsert_placement ":collection='Cal'" ":seq=1" ":link_id='ev'" ":hash=NULL" > /dev/null
isearch insert_occurrence ":collection='Cal'" ":seq=1" ":start='2026-09-01T00:00:00Z'" ":end='2026-09-01T00:00:00Z'"
day=(":start='2026-09-01T00:00:00Z'" ":end='2026-09-02T00:00:00Z'")
expect "occurrence: a zero-length one at the start of a range is in it, one at its end is not" \
    "$(isearch occurring_between "${day[@]}")|$(isearch occurring_between ":start='2026-08-31T00:00:00Z'" ":end='2026-09-01T00:00:00Z'")" "Cal|1|"

expect "feed: a batch reads each row's stamp, the cursor it may record" \
    "$(isearch load_changed_items ":since=0" ":limit=10" | cut -d'|' -f2,10 | tr '\n' ' ')" \
    "$(sql "SELECT link_id || '|' || changed FROM items ORDER BY changed;" | tr '\n' ' ')"

# --- An expansion a bound stopped says where (SEARCH.md §7, §8.2) ----------

isearch upsert_placement ":collection='Cal2'" ":seq=3" ":link_id='other'" ":hash=NULL" > /dev/null
isearch set_cut ":collection='Cal'" ":seq=1" ":cut='2026-09-01T00:00:00Z'"
expect "cut: an item cut before a range's end counts in its collections, one cut at or after it does not, and a range open there counts it" \
    "$(isearch cut_before ":collections='[\"Cal\"]'" ":end='2026-09-02T00:00:00Z'")|$(isearch cut_before ":collections='[\"Cal\"]'" ":end='2026-09-01T00:00:00Z'")|$(isearch cut_before ":collections='[\"Cal2\"]'" ":end=NULL")|$(isearch cut_before ":collections='[\"Cal\",\"Cal2\"]'" ":end=NULL")" \
    "1|0|0|1"
steps="$(isplan cut_before ":collections='[\"Cal\"]'" ":end=NULL")"
isearch set_cut ":collection='Cal'" ":seq=1" ":cut=NULL"
expect "cut: an item expanded again within the bounds is no longer counted, the count seeking placement_cut" \
    "$(isearch cut_before ":collections='[\"Cal\"]'" ":end=NULL")|$(grep -c 'USING COVERING INDEX placement_cut (collection=?' <<<"$steps" || true)" "0|1"

# --- A calendar item's attachment field is read by a seek (SEARCH.md §6, §8) -

fresh
index
body "$ha" ":attachment=1" > /dev/null
body "$hn" > /dev/null
isearch upsert_placement ":collection='Cal'" ":seq=1" ":link_id='attach'" ":hash='$ha'" > /dev/null
isearch upsert_placement ":collection='Cal'" ":seq=2" ":link_id='plain'" ":hash='$hn'" > /dev/null
isearch upsert_placement ":collection='Cal'" ":seq=3" ":link_id='bare'" ":hash=NULL" > /dev/null
expect "attached: a body whose attachment field holds text answers, an empty field and no body do not" \
    "$(isearch attached | tr '\n' ' ')|$(sqlite3 "$dir/index.db" "INSERT INTO object(hash, status) VALUES('$hx', 'ok');" 2>&1 | grep -c 'NOT NULL')" "Cal|1 |1"

# --- What a card holds is read by a seek (SEARCH.md §6, §8) ----------------

fresh
index
tel_id="$(body "$ct" ":tel=1")"
full_id="$(body "$cf" ":adr=1" ":bday=1" ":photo=1")"
isearch insert_object_category ":object=$full_id" ":value='family'"
isearch insert_object_category ":object=$full_id" ":value='family'"
isearch insert_object_category ":object=$full_id" ":value='flat'"
isearch upsert_placement ":collection='Contacts'" ":seq=1" ":link_id='tel'" ":hash='$ct'" > /dev/null
isearch upsert_placement ":collection='Contacts'" ":seq=2" ":link_id='full'" ":hash='$cf'" > /dev/null
expect "holding: each property answers the cards holding it alone" \
    "$(for p in phone address birthday photo; do isearch holding ":property='$p'" | tr '\n' ' '; done)" \
    "Contacts|1 Contacts|2 Contacts|2 Contacts|2 "
expect "categorised: a value stated twice is one row, and a value matches whole" \
    "$(isearch categorised ":value='family'" | tr '\n' ' ')|$(isearch categorised ":value='fam'")" "Contacts|2 |"
isearch delete_object ":rowid=$full_id"
isearch delete_object_row ":hash='$cf'"
expect "object_category: a card's categories go with its object" \
    "$(sqlite3 "$dir/index.db" "SELECT count(*) FROM object_category;")" "0"

# --- An agenda reads occurrences in time order (SEARCH.md §7) ---------------

fresh
index
isearch upsert_placement ":collection='Cal'" ":seq=2" ":link_id='series'" ":hash=NULL" > /dev/null
isearch upsert_placement ":collection='Cal'" ":seq=1" ":link_id='due'" ":hash=NULL" > /dev/null
isearch insert_occurrence ":collection='Cal'" ":seq=2" ":start='2026-09-08T09:00:00Z'" ":end='2026-09-08T10:00:00Z'"
isearch insert_occurrence ":collection='Cal'" ":seq=2" ":start='2026-09-01T09:00:00Z'" ":end='2026-09-01T10:00:00Z'"
isearch insert_occurrence ":collection='Cal'" ":seq=1" ":start='2026-09-01T09:00:00Z'" ":end='2026-09-01T09:00:00Z'"
isearch insert_occurrence ":collection='Cal'" ":seq=1" ":start='2026-09-15T00:00:00Z'" ":end='2026-09-15T00:00:00Z'"
isearch insert_occurrence ":collection='Cal'" ":seq=1" ":start='2026-09-10T09:00:00Z'" ":end='2026-09-10T09:30:00Z'"
isearch insert_occurrence ":collection='Cal'" ":seq=2" ":start='2026-09-01T00:00:00Z'" ":end='2026-09-01T00:00:00Z'"
isearch insert_occurrence ":collection='Cal'" ":seq=1" ":start='2026-08-31T23:00:00Z'" ":end='2026-09-01T00:00:00Z'"
expect "occurrences_between: one row per occurrence, by start then seq, a zero-length one at the range's start kept, one ending there and one at its end left out" \
    "$(isearch occurrences_between ":start='2026-09-01T00:00:00Z'" ":end='2026-09-15T00:00:00Z'" | tr '\n' ' ')" \
    "Cal|2|2026-09-01T00:00:00Z|2026-09-01T00:00:00Z Cal|1|2026-09-01T09:00:00Z|2026-09-01T09:00:00Z Cal|2|2026-09-01T09:00:00Z|2026-09-01T10:00:00Z Cal|2|2026-09-08T09:00:00Z|2026-09-08T10:00:00Z Cal|1|2026-09-10T09:00:00Z|2026-09-10T09:30:00Z "
expect "occurrences_between: an agenda seeks occurrence_by_start below the range's end" \
    "$(isplan occurrences_between ":start='2026-09-01T00:00:00Z'" ":end='2026-09-15T00:00:00Z'" | grep -c 'SEARCH occurrence USING INDEX occurrence_by_start (start<?)' || true)" "1"

# --- A rename a cut pass folded past is still reconciled (SEARCH.md §4, §8.2) -

fresh
index
collection INBOX
item INBOX a 1
isearch init_index_meta ":version=1" ":tokenizer='unicode61 remove_diacritics 0'"
isearch upsert_placement ":collection='INBOX'" ":seq=1" ":link_id='a'" ":hash=NULL" > /dev/null
head="$(run read/load_change_cursor | cut -d'|' -f1)"
purges="$(run read/load_change_cursor | cut -d'|' -f2)"
isearch set_index_cursor ":store_change=$head" ":store_purges=$purges"
expect "behind: an index a pass completed over every stamp is not behind" "$(isearch behind)" "0"
run owner/rename_collection ":collection='INBOX'" ":new_id='Archive'"
moved="$(run read/load_change_cursor | cut -d'|' -f1)"
expect "behind: a rename draws the stamps the index has yet to fold" "$(isearch behind)" "$((moved - head))"
# A batch folds the restamped item, records its stamp, and the deadline cuts
# the pass before it completes.
isearch set_index_cursor ":store_change=$moved" ":store_purges=$purges"
expect "reconciled: past a batch, the store's purge count still stands above the one the index recorded, so the next pass reconciles the old id" \
    "$(isearch load_index_meta | cut -d'|' -f4)|$(run read/load_change_cursor | cut -d'|' -f2)|$(isearch behind)|$(isearch placements_gone)" \
    "$purges|$((purges + 1))|0|INBOX|1|a"

# --- An index names its version and shape, and its store (SEARCH.md §2) -----

fresh
index
isearch init_index_meta ":version=1" ":tokenizer='unicode61 remove_diacritics 0'"
expect "index: init_index_meta stamps this draft and the canonical shape, which load_index_meta answers" \
    "$(isearch load_index_meta | cut -d'|' -f10,11)" "search-draft-09|canonical"
expect "index: init_index_meta records the store and the incarnation it is built from" \
    "$(isearch load_index_meta | cut -d'|' -f8,9)" "$(run read/load_change_cursor | cut -d'|' -f3,4)"
run owner/raise_incarnation ":replaced=NULL"
expect "index: a restored store answers another incarnation than the one the index recorded" \
    "$(isearch load_index_meta | cut -d'|' -f9)|$(run read/load_change_cursor | cut -d'|' -f4)" "1|2"

# --- A body that cannot be read is tried again (SEARCH.md §4) ---------------

fresh
index
collection INBOX
object "$h1"
item INBOX m 1 "$h1"
isearch init_index_meta ":version=1" ":tokenizer='unicode61 remove_diacritics 0'"
# The pass finds the blob gone: the placement indexed bodiless, recorded.
isearch upsert_placement ":collection='INBOX'" ":seq=1" ":link_id='m'" ":hash=NULL" > /dev/null
isearch insert_missing ":collection='INBOX'" ":seq=1"
isearch insert_missing ":collection='INBOX'" ":seq=1"
head="$(run read/load_change_cursor | cut -d'|' -f1)"
isearch set_index_cursor ":store_change=$head" ":store_purges=0"
expect "missing: a placement whose body could not be read is folded again by the next pass, though the store stamped nothing" \
    "$(isearch load_changed_items ":since=$head" ":limit=10")|$(isearch load_missing_items | cut -d'|' -f1-4)" "|INBOX|m|1|$h1"
isearch delete_missing ":collection='INBOX'" ":seq=1"
expect "missing: a placement whose body is indexed leaves it" "$(isearch load_missing_items)" ""
isearch insert_missing ":collection='INBOX'" ":seq=1"
isearch delete_placement ":collection='INBOX'" ":seq=1" > /dev/null
expect "missing: a placement deleted takes its row" "$(sqlite3 "$dir/index.db" "SELECT count(*) FROM missing;")" "0"

# --- A message that leaves prunes its thread (SEARCH.md §9) ----------------

fresh
index
collection INBOX
for spec in r@x:1:2026-09-01 x@x:2:2026-09-02 y@x:3:2026-09-03 z@x:4:2026-09-04; do
    IFS=: read -r link seq when <<<"$spec"
    item INBOX "$link" "$seq"
    sql "UPDATE items SET sort_key = '${when}T00:00:00Z' WHERE link_id = '$link';"
    isearch upsert_placement ":collection='INBOX'" ":seq=$seq" ":link_id='$link'" ":hash=NULL" > /dev/null
done
# r <- x <- y, one thread named r; z replies to w, which nobody holds.
isearch upsert_thread ":id='r@x'" ":first='2026-09-01T00:00:00Z'" ":last='2026-09-03T00:00:00Z'" ":count=3"
isearch upsert_thread ":id='z@x'" ":first='2026-09-04T00:00:00Z'" ":last='2026-09-04T00:00:00Z'" ":count=1"
for spec in r@x:r@x: x@x:r@x:r@x y@x:r@x:x@x z@x:z@x:w@x w@x:z@x:; do
    IFS=: read -r link thread parent <<<"$spec"
    isearch upsert_message ":link_id='$link'" ":thread='$thread'" ":parent=$([ -n "$parent" ] && echo "'$parent'" || echo NULL)"
done
# r and z are purged from the store; the key reconciliation drops their
# placements.
sql "UPDATE items SET deleted = 1, retained_at = '2026-10-01T00:00:00Z' WHERE link_id IN ('r@x', 'z@x');"
run owner/purge_item ":collection='INBOX'" ":seq=1" > /dev/null
run owner/purge_item ":collection='INBOX'" ":seq=4" > /dev/null
gone="$(isearch placements_gone | tr '\n' ' ')"
for seq in 1 4; do
    isearch delete_placement ":collection='INBOX'" ":seq=$seq" > /dev/null
done
for thread in r@x z@x; do
    isearch unparent_messages ":thread='$thread'"
done
expect "thread: a message no placement holds names no parent, and goes once no row names it, its phantom parent with it" \
    "$gone|$(isearch prune_messages ":thread='r@x'")|$(isearch prune_messages ":thread='z@x'" | sort | tr '\n' ' ')" \
    "INBOX|1|r@x INBOX|4|z@x ||w@x z@x "
expect "thread: thread_rows reads each row's parent and a held one's sort key, so the re-keying finds the lowest present member" \
    "$(isearch thread_rows ":thread='r@x'" | tr '\n' ' ')" \
    "r@x|| x@x|r@x|2026-09-02T00:00:00Z y@x|x@x|2026-09-03T00:00:00Z "
expect "thread: a thread row a member still names is kept" \
    "$(isearch delete_thread ":id='r@x'"; sqlite3 "$dir/index.db" "SELECT count(*) FROM thread WHERE id = 'r@x';")" "1"
# The re-keying: one connected set, named by x, the lowest present member.
isearch upsert_thread ":id='x@x'" ":first='2026-09-02T00:00:00Z'" ":last='2026-09-03T00:00:00Z'" ":count=2"
for spec in r@x: x@x:r@x y@x:x@x; do
    IFS=: read -r link parent <<<"$spec"
    isearch upsert_message ":link_id='$link'" ":thread='x@x'" ":parent=$([ -n "$parent" ] && echo "'$parent'" || echo NULL)"
done
isearch delete_thread ":id='r@x'"
isearch delete_thread ":id='z@x'"
expect "thread: what is left is what a rebuild from the store as it stands writes, no id, parent nor thread of a purged message's own" \
    "$(sqlite3 "$dir/index.db" "SELECT link_id || '>' || ifnull(parent, '') || '@' || thread FROM message ORDER BY link_id;" | tr '\n' ' ')|$(sqlite3 "$dir/index.db" "SELECT group_concat(id, ' ') FROM thread;")" \
    "r@x>@x@x x@x>r@x@x@x y@x>x@x@x@x |x@x"
steps="$(isplan prune_messages ":thread='r@x'")$(isplan unparent_messages ":thread='r@x'")"
expect "thread: the prune seeks the thread's rows, never every message" \
    "$(grep -c 'SCAN message' <<<"$steps" || true)$(grep -c 'message_by_thread (thread=?)' <<<"$steps" || true)" "02"

# --- A page reads a term's best bodies or probes one (SEARCH.md §8.2) ------

fresh
index
for spec in 1:h1:budget-budget-budget 2:h2:budget-and-many-other-words-around-it 3:h3:nothing; do
    IFS=: read -r seq label words <<<"$spec"
    hash="${!label}"
    id="$(body "$hash")"
    text "$id" "" "${words//-/ }"
    isearch upsert_placement ":collection='INBOX'" ":seq=$seq" ":link_id='m$seq'" ":hash='$hash'" > /dev/null
done
summary_id="$(isearch upsert_placement ":collection='INBOX'" ":seq=4" ":link_id='m4'" ":hash=NULL")"
isearch insert_summary_text ":rowid=$summary_id" ":title='forecast'" ":people=''" ":from=''" ":to=''" ":cc=''" ":bcc=''" \
    ":email=''" ":organizer=''" ":attendee=''"
expect "ranked: a page of the bodies a term matches best, best first, the next page after it" \
    "$(isearch match_objects_ranked ":match='\"budget\"'" ":limit=1" ":offset=0" | cut -d'|' -f1,2)|$(isearch match_objects_ranked ":match='\"budget\"'" ":limit=1" ":offset=1" | cut -d'|' -f1,2)|$(isearch match_objects_ranked ":match='\"budget\"'" ":limit=5" ":offset=2")" \
    "INBOX|1|INBOX|2|"
steps="$(isplan match_objects_ranked ":match='\"budget\"'" ":limit=1" ":offset=0")"
expect "ranked: FTS5 orders by rank and keeps the page, sorting nothing itself" \
    "$(grep -c 'TEMP B-TREE FOR ORDER BY' <<<"$steps" || true)$(grep -c 'SCAN object_text VIRTUAL TABLE' <<<"$steps" || true)" "01"
expect "probe: one body, or one summary, tested against a term" \
    "$(isearch match_object ":match='\"budget\"'" ":hash='$h2'")|$(isearch match_object ":match='\"budget\"'" ":hash='$h3'")|$(isearch match_summary ":match='{title} : \"fore\" *'" ":collection='INBOX'" ":seq=4")|$(isearch match_summary ":match='\"budget\"'" ":collection='INBOX'" ":seq=4")" \
    "1||1|"
steps="$(isplan match_object ":match='\"budget\"'" ":hash='$h2'")$(isplan match_summary ":match='\"budget\"'" ":collection='INBOX'" ":seq=4")"
expect "probe: each seeks the term's matches by rowid, never every match" \
    "$(grep -cE 'VIRTUAL TABLE INDEX [0-9]+:=M' <<<"$steps" || true)" "2"

# --- A hit is a live placement's; a term matches bodies, summaries (SEARCH §8)

fresh
index
collection INBOX "'work'"
collection Archive "'work'"
object "$h1"
item INBOX a 1 "'$h1'"
item INBOX b 2
item Archive a 1 "'$h1'"
item INBOX s 3
sql "UPDATE items SET deleted = 1 WHERE link_id = 'b';"
expect "hit: a live placement's presentation row out of the store, a tombstone's none" \
    "$(isearch hit ":collection='INBOX'" ":seq=1" | cut -d'|' -f1-5,7)|$(isearch hit ":collection='INBOX'" ":seq=2")" \
    "INBOX|work|message/rfc822|1|a|$h1|"
id="$(body "$h1")"
text "$id" "quarterly" "alpha words"
other="$(body "$h9")"
text "$other" "" "beta"
for spec in INBOX:1:a Archive:1:a; do
    IFS=: read -r collection seq link <<<"$spec"
    isearch upsert_placement ":collection='$collection'" ":seq=$seq" ":link_id='$link'" ":hash='$h1'" > /dev/null
done
summary_id="$(isearch upsert_placement ":collection='INBOX'" ":seq=3" ":link_id='s'" ":hash=NULL")"
isearch insert_summary_text ":rowid=$summary_id" ":title='forecast'" ":people=''" ":from=''" ":to=''" ":cc=''" ":bcc=''" \
    ":email=''" ":organizer=''" ":attendee=''"
expect "match: a compiled term answers every placement of each body it matches, in its field alone, ranked" \
    "$(isearch match_objects ":match='\"alpha\"'" | cut -d'|' -f1,2 | sort | tr '\n' ' ')|$(isearch match_objects ":match='{title} : \"alpha\"'")|$(isearch match_objects ":match='{title} : \"quarterly\"'" | cut -d'|' -f1 | sort | tr '\n' ' ')|$(isearch match_objects ":match='\"alpha\"'" | cut -d'|' -f3 | grep -c '^-[0-9]')" \
    "Archive|1 INBOX|1 ||Archive INBOX |2"
expect "match: a compiled term answers the bodiless placements whose summary matches, a body's never" \
    "$(isearch match_summaries ":match='{title} : \"forecast\"'" | cut -d'|' -f1,2)|$(isearch match_summaries ":match='\"alpha\"'")" "INBOX|3|"
isearch delete_summary_text ":rowid=$summary_id"
expect "match: a summary's text deleted matches no more" "$(isearch match_summaries ":match='\"forecast\"'")" ""
expect "object: object_indexed answers a body's id and status, nothing for a body never indexed" \
    "$(isearch object_indexed ":hash='$h1'")|$(isearch object_indexed ":hash='$h2'")" "$id|ok|"
expect "object: objects_gone lists an indexed body the store holds no more" "$(isearch objects_gone)" "$h9"

# --- Threads per account; flags and occurrences replaced whole (SEARCH §7, §9)

fresh
index
collection Work "'work'"
collection Home "'home'"
item Work r@x 1
item Work x@x 2
item Home r@x 1
for spec in Work:1:r@x Work:2:x@x Home:1:r@x; do
    IFS=: read -r collection seq link <<<"$spec"
    isearch upsert_placement ":collection='$collection'" ":seq=$seq" ":link_id='$link'" ":hash=NULL" > /dev/null
done
isearch upsert_thread ":id='r@x'" ":first='2026-09-01T00:00:00Z'" ":last='2026-09-02T00:00:00Z'" ":count=2"
for spec in r@x: x@x:r@x w@x:; do
    IFS=: read -r link parent <<<"$spec"
    isearch upsert_message ":link_id='$link'" ":thread='r@x'" ":parent=$([ -n "$parent" ] && echo "'$parent'" || echo NULL)"
done
expect "thread: thread_of names a message's thread, thread_members its present members in one account, a phantom none" \
    "$(isearch thread_of ":link_id='x@x'")|$(isearch thread_of ":link_id='nobody@x'")|$(isearch thread_members ":thread='r@x'" ":account='work'" | sort | tr '\n' ' ')|$(isearch thread_members ":thread='r@x'" ":account='home'" | tr '\n' ' ')" \
    "r@x||Work|1 Work|2 |Home|1 "
isearch insert_flag ":flag='\\Seen'" ":collection='Work'" ":seq=1"
isearch insert_flag ":flag='\\Flagged'" ":collection='Work'" ":seq=1"
isearch insert_flag ":flag='\\Seen'" ":collection='Work'" ":seq=2"
expect "flag: flagged answers the placements holding a flag" \
    "$(isearch flagged ":flag='\\Seen'" | sort | tr '\n' ' ')|$(isearch flagged ":flag='\\Flagged'")" "Work|1 Work|2 |Work|1"
isearch replace_flags ":collection='Work'" ":seq=1"
expect "flag: replace_flags clears one placement's flags, another's kept" \
    "$(isearch flagged ":flag='\\Seen'" | tr '\n' ' ')|$(isearch flagged ":flag='\\Flagged'")" "Work|2 |"
for spec in Work:1:2026-09-01 Work:1:2026-09-08 Work:2:2026-09-02; do
    IFS=: read -r collection seq day <<<"$spec"
    isearch insert_occurrence ":collection='$collection'" ":seq=$seq" ":start='${day}T09:00:00Z'" ":end='${day}T10:00:00Z'"
done
isearch replace_occurrences ":collection='Work'" ":seq=1"
expect "occurrence: replace_occurrences clears one placement's occurrences, another's kept" \
    "$(isearch occurrences_between ":start='2026-08-01T00:00:00Z'" ":end='2026-10-01T00:00:00Z'" | cut -d'|' -f1-3 | tr '\n' ' ')" \
    "Work|2|2026-09-02T09:00:00Z "

# --- A reference is read either way from the store (SEARCH.md §8) ----------

fresh
index
collection INBOX
run owner/set_collection_kind ":collection='Cal'" ":account=NULL" ":kind='text/calendar'"
item INBOX m@x 1
item Cal ev@x 2
item Cal gone@x 3
for to in ev@x gone@x; do
    run owner/add_reference ":from_kind='message/rfc822'" ":from_link_id='m@x'" ":to_kind='text/calendar'" \
        ":to_link_id='$to'" ":role='invitation'" ":origin='auto'" > /dev/null
done
sql "UPDATE items SET deleted = 1 WHERE link_id = 'gone@x';"
expect "linked: the live placements at the other end of an item's references, either way, under a role or any" \
    "$(isearch linked ":kind='message/rfc822'" ":link_id='m@x'" ":role=NULL" | tr '\n' ' ')|$(isearch linked ":kind='text/calendar'" ":link_id='ev@x'" ":role='invitation'")|$(isearch linked ":kind='text/calendar'" ":link_id='ev@x'" ":role='parent'")|$(isearch linked ":kind='message/rfc822'" ":link_id='ev@x'" ":role=NULL")" \
    "Cal|2 |INBOX|1||"

# --- Erasing: a purge leaves nothing in the files (STORAGE.md §11.5) ----------

# erase <secure_delete> <merge>: a mail whose key, subject and body words no
# other row holds, beside one that stays, purged as §11.5 runs it, its index
# rows deleted, the text merged by optimize_text when merge is 1; answers how
# often its word is left in pimdir.db, then in index.db.
erase() {
    secure_delete="$1"
    fresh
    index
    collection INBOX
    for spec in 1:kept 2:zanzibar; do
        IFS=: read -r seq word <<<"$spec"
        mail INBOX "$word@x" "$seq" "$seq" "'2026-09-0${seq}T00:00:00Z'"
        label="h$seq"
        id="$(body "${!label}")"
        text "$id" "$word report" "$word minutes"
        isearch upsert_placement ":collection='INBOX'" ":seq=$seq" ":link_id='$word@x'" ":hash='${!label}'" > /dev/null
    done
    run owner/delete_item_bindings ":collection='INBOX'" ":link_id='zanzibar@x'"
    run owner/retain_item ":collection='INBOX'" ":link_id='zanzibar@x'" ":source='imap'"
    run owner/purge_item ":collection='INBOX'" ":seq=2" > /dev/null
    isearch delete_placement ":collection='INBOX'" ":seq=2" > /dev/null
    isearch delete_object ":rowid=$id"
    isearch delete_object_row ":hash='$h2'"
    [ "$2" = 0 ] || isearch optimize_text
    echo "$(grep -ao zanzibar "$dir/pimdir.db" | wc -l)|$(grep -ao zanzibar "$dir/index.db" | wc -l)"
}
expect "erase: a purged mail's key, subject and address leave pimdir.db, and its body's words index.db, once secure_delete zeroes what a delete frees and optimize_text merges the full-text segments" \
    "$(erase ON 1)" "0|0"
expect "erase: without optimize_text the deleted body's words stay in a full-text segment" \
    "$(erase ON 0 | cut -d'|' -f2 | grep -c '^0$' || true)" "0"
expect "erase: without secure_delete a purged row stays in the space its delete freed, in both files" \
    "$(erase OFF 1 | tr '|' '\n' | grep -c '^0$' || true)" "0"
secure_delete=ON

# --- A store from elsewhere opens with its schema untrusted (STORAGE.md §18) --

untrusted=1
fresh
index
collection INBOX
mail INBOX m@x 1 1 "'2026-09-01T00:00:00Z'" '["\\Seen"]'
id="$(body "$h1")"
text "$id" "untrusted" "words"
isearch upsert_placement ":collection='INBOX'" ":seq=1" ":link_id='m@x'" ":hash='$h1'" > /dev/null
run owner/delete_item_bindings ":collection='INBOX'" ":link_id='m@x'"
run owner/retain_item ":collection='INBOX'" ":link_id='m@x'" ":source='imap'"
expect "untrusted: the canonical schemas' triggers and statements run with trusted_schema off and the defensive flag on" \
    "$(run owner/purge_item ":collection='INBOX'" ":seq=1" 2>&1 | wc -l)|$(isearch delete_object ":rowid=$id" 2>&1)|$(isearch optimize_text 2>&1)|$(sql "SELECT changed > 0 FROM collections WHERE id = 'INBOX'; SELECT purges FROM store_meta;" | tr '\n' ' ')" \
    "1|||1 1 "
untrusted=0

# --- The system flags are bits, every other flag a row (STORAGE.md §4.3, §13)

fresh
collection INBOX
mail INBOX a 1 10 "'2026-08-01T10:00:00Z'" '["\\Seen", "\\seen", "$label", "\\Flagged"]' '["\\Seen", "$label"]'
expect "bits: the system flags take the item's bits by their exact bytes, any other flag a row" \
    "$(sql "SELECT marks FROM items WHERE link_id = 'a';")|$(sql "SELECT group_concat(flag, ' ') FROM (SELECT flag FROM placement_flag ORDER BY flag);")|$(flags INBOX a)" \
    "5|\$label \\seen|\$label \\Flagged \\Seen \\seen"
expect "bits: a read answers the bits and the rows as one set" \
    "$(run read/get_item ":collection='INBOX'" ":seq=1" | cut -d'|' -f3 | tr ' ' '\n' | LC_ALL=C sort | tr '\n' ' ')" \
    "\$label \\Flagged \\Seen \\seen "
expect "bits: a base keeps its system flags in base_marks, the rest as rows" \
    "$(sql "SELECT base_marks FROM bindings;")|$(base_flags INBOX a imap)" "1|\$label \\Seen"
expect "bits: an unknown set holds no bit" \
    "$(sql "INSERT INTO items(collection, link_id, seq, flags_known, marks, level) VALUES('INBOX', 'u', 2, 0, 1, 1);" 2>&1 | grep -c 'CHECK constraint failed')" "1"

# --- A delta loads what owes a push beside its page (STORAGE.md §14, SYNC.md §10)

fresh
collection INBOX
object "$h1"
mail INBOX clean 1 10 "''" '["\\Seen"]' '["\\Seen"]'
mail INBOX seen 2 20 "''" '["\\Seen"]' '[]'
mail INBOX label 3 30 "''" '["$x"]' '[]'
mail INBOX unknown 4 40 "''" '["\\Seen"]' '[]'
mail INBOX bound 5 50 "''"
mail INBOX diverged 6 60 "''"
mail INBOX deleted 7 70 "''"
mail INBOX created 8 80 "''"
mail INBOX edited 9 90 "''"
sql "UPDATE items SET flags_known = 0, marks = 0 WHERE link_id = 'unknown';
     UPDATE bindings SET conflicted = 1 WHERE item IN (SELECT id FROM items WHERE link_id = 'bound');
     UPDATE items SET conflicted = 1 WHERE link_id = 'diverged';
     UPDATE items SET deleted = 1 WHERE link_id = 'deleted';
     UPDATE bindings SET base_present = 0, base_flags_known = 0, base_marks = 0 WHERE item IN (SELECT id FROM items WHERE link_id = 'created');
     UPDATE items SET object_hash = '$h1', level = 2 WHERE link_id = 'edited';
     INSERT INTO bindings(item, collection, source, handle, base_present) VALUES((SELECT id FROM items WHERE link_id = 'seen'), 'INBOX', 'graph', 'g20', 1);"
run owner/recompute_refcounts
expect "owing: every binding of the source not Clean, and no other, an unknown set holding no opinion" \
    "$(run owner/list_owing_bindings ":collection='INBOX'" ":source='imap'" | tr '\n' ' ')|$(run owner/list_owing_bindings ":collection='INBOX'" ":source='graph'" | tr '\n' ' ')" \
    "20 30 50 60 70 80 90 |"
expect "lacking: the live items holding a body a source binds not" \
    "$(run owner/list_lacking_items ":collection='INBOX'" ":source='graph'" | tr '\n' ' ')|$(run owner/list_lacking_items ":collection='INBOX'" ":source='imap'" | tr '\n' ' ')" \
    "edited |"
expect "owing: the source's bindings seek bindings_by_handle, never the whole store" \
    "$(plan owner/list_owing_bindings ":collection='INBOX'" ":source='imap'" | grep -c 'bindings_by_handle (collection=? AND source=?)' || true)" "1"

# --- The sender rule runs once per page (STORAGE.md §14.2) ------------------

fresh
collection INBOX
run owner/set_collection_kind ":collection='Cards'" ":account=NULL" ":kind='text/vcard'"
mail INBOX m1 1 10 "''"
mail INBOX m2 2 20 "''"
mail INBOX m3 3 30 "''"
run owner/insert_item ":collection='Cards'" ":link_id='c1'" ":seq=4" ":flags='[]'" ":object_hash=NULL" \
    ":sort_key=''" ":level=1" ":deleted=0" ":conflicted=0" ":conflict_object=NULL"
for link in m1 m2 m3; do
    run owner/insert_address ":collection='INBOX'" ":link_id='$link'" ":role='from'" ":position=0" \
        ":address='alice@example.org'" ":name=NULL"
done
run owner/insert_address ":collection='Cards'" ":link_id='c1'" ":role='email'" ":position=0" \
    ":address='alice@example.org'" ":name=NULL"
run owner/link_senders_of_by_link ":links='[\"m1\", \"m3\"]'"
expect "senders: the page's mail is tied to its senders' cards, and no other mail" \
    "$(sql "SELECT group_concat(from_link_id || '>' || to_link_id, ' ') FROM (SELECT * FROM item_reference ORDER BY from_link_id);")" \
    "m1>c1 m3>c1"

# --- Every statement runs (AGENTS.md §4) --------------------------------------

# Every statement under queries/ ran in a scenario above, or is waived with its
# reason, one `part/profile/name: reason` a line of the waiver file; a waiver
# naming no statement, or one a scenario runs, fails too, so the list holds
# only what no scenario can run.
ran="$(sort -u "$dir/ran")"
all="$(cd "$root/queries" && find . -name '*.sql' | sed 's|^\./||; s|\.sql$||' | sort)"
waived="$(sed '/^#/d; /^$/d' "$waivers" | sort)"
while read -r line; do
    [ -n "$line" ] || continue
    name="${line%%: *}"
    if [ "$name" = "$line" ] || [ -z "${line#*: }" ]; then
        echo "$line: a waiver names a statement and its reason, colon separated" >&2
        failures=$((failures + 1))
    elif ! grep -qxF "$name" <<<"$all"; then
        echo "$name: waived, and no statement under queries/" >&2
        failures=$((failures + 1))
    elif grep -qxF "$name" <<<"$ran"; then
        echo "$name: waived, yet a scenario runs it" >&2
        failures=$((failures + 1))
    fi
done <<<"$waived"
while read -r name; do
    if ! grep -qxF "$name" <<<"$ran" && ! grep -q "^$name: " <<<"$waived"; then
        echo "$name: run by no scenario, and waived nowhere" >&2
        failures=$((failures + 1))
    fi
done <<<"$all"

if [ "$failures" -gt 0 ]; then
    echo "$failures invariant(s) broken" >&2
    exit 1
fi

echo "every invariant scenario holds, $(grep -cxF -f <(echo "$all") <<<"$ran") of $(grep -c . <<<"$all") statements run, $(grep -c . <<<"$waived" || true) waived"
