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
rehearsal="${3:-$root/checks/rehearsal}"
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

# takes <part/profile/name> [:param=literal...]: records each binding the
# statement does not take, a parameter of its text or a list slot it reads
# (§4.4): SQLite binds NULL to a parameter no binding names, so a scenario
# still spelling a renamed parameter would run on NULL and prove nothing. The
# gate at the end fails on any.
takes() {
    local file="$1" binding name text; shift
    text="$(sed 's/--.*//' "$root/queries/$file.sql")"
    for binding in "$@"; do
        name="${binding%%=*}"
        case "$name" in
            .* | :flags | :base_flags) ;;
            *) grep -qE "$name\b|slot = '${name#:}'" <<<"$text" || echo "$file binds $name" >> "$dir/stray" ;;
        esac
    done
}

run() {
    local file="$1"; shift
    local after=""
    takes "storage/$file" "$@"
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
    "$(run owner/held_elsewhere ":collection='INBOX'" ":link_id='a'" ":hash='$h1'")" "1"
sql "UPDATE items SET object = (SELECT id FROM objects WHERE hash = '$h2') WHERE collection = 'Archive';"
expect "move: a holder with another body is not" \
    "$(run owner/held_elsewhere ":collection='INBOX'" ":link_id='a'" ":hash='$h1'")" ""
sql "UPDATE items SET object = NULL WHERE collection = 'Archive';"
expect "move: a bodiless holder does not take the only body" \
    "$(run owner/held_elsewhere ":collection='INBOX'" ":link_id='a'" ":hash='$h1'")" ""
# A bodiless retiring message is held elsewhere only by a row that agrees with
# it (§9, §11.1): the same subject, date and sender, NULL matching NULL. A
# holder stating another, or either row holding no summary, is another message
# reusing the Message-ID, and the row is retained. Another kind agrees with
# anything.
said() {
    run owner/upsert_mail_summary ":collection='$1'" ":link_id='a'" ":message_id='a'" ":subject=$2" \
        ":sender=$3" ":sender_name=NULL" ":date=$4" ":size=$5" ":attachment=NULL" ":invitation=NULL"
}
bodiless() {
    run owner/held_elsewhere ":collection='INBOX'" ":link_id='a'" ":hash=NULL"
}
expect "move: a bodiless retiring message is held by no row while neither states a summary" "$(bodiless)" ""
said INBOX "'Notice'" "'cron@x'" "'2026-08-01T10:00:00Z'" 10
expect "move: nor by a holder stating no summary" "$(bodiless)" ""
said Archive "'Notice'" "'cron@x'" "'2026-08-01T10:00:00Z'" NULL
expect "move: a bodiless retiring message is held by a holder agreeing on subject, date and sender, whatever its size" \
    "$(bodiless)" "1"
said Archive "'Notice'" "'cron@x'" "'2026-08-02T10:00:00Z'" 10
expect "move: a holder stating another date is another message" "$(bodiless)" ""
said Archive "'notice'" "'cron@x'" "'2026-08-01T10:00:00Z'" 10
expect "move: a holder stating another subject, compared byte for byte, is another message" "$(bodiless)" ""
said Archive "'Notice'" "NULL" "'2026-08-01T10:00:00Z'" 10
expect "move: a holder stating no sender beside one is another message" "$(bodiless)" ""
said INBOX "'Notice'" "NULL" "NULL" 10
said Archive "'Notice'" "NULL" "NULL" 20
expect "move: an unknown date and sender match unknown ones" "$(bodiless)" "1"
sql "UPDATE items SET object = (SELECT id FROM objects WHERE hash = '$h1') WHERE collection = 'Archive';"
said Archive "'Other'" "'dan@x'" "'2026-08-03T09:00:00Z'" 1
expect "move: a holder carrying the retiring body is the same message whatever its row states, and no holder of another body is" \
    "$(run owner/held_elsewhere ":collection='INBOX'" ":link_id='a'" ":hash='$h1'")|$(run owner/held_elsewhere ":collection='INBOX'" ":link_id='a'" ":hash='$h2'")" "1|"
sql "UPDATE items SET deleted = 1 WHERE collection = 'Archive';"
said Archive "'Notice'" "NULL" "NULL" 10
expect "move: a tombstone holds nothing" "$(bodiless)" ""
run owner/set_collection_kind ":collection='Cards'" ":account=NULL" ":kind='text/vcard'"
run owner/set_collection_kind ":collection='Cards2'" ":account=NULL" ":kind='text/vcard'"
run owner/insert_item ":collection='Cards'" ":link_id='u'" ":seq=5" ":flags='[]'" ":object_hash=NULL" ":sort_key=''" ":level=1" ":deleted=0" ":conflicted=0" ":conflict_object=NULL"
run owner/insert_item ":collection='Cards2'" ":link_id='u'" ":seq=5" ":flags='[]'" ":object_hash=NULL" ":sort_key=''" ":level=1" ":deleted=0" ":conflicted=0" ":conflict_object=NULL"
expect "move: a bodiless retiring row of another kind is held by any live holder" \
    "$(run owner/held_elsewhere ":collection='Cards'" ":link_id='u'" ":hash=NULL")" "1"
steps="$(plan owner/held_elsewhere ":collection='INBOX'" ":link_id='a'" ":hash=NULL")"
expect "move: held_elsewhere seeks the holders on items_by_link and each summary by its key, scanning nothing" \
    "$(grep -c 'SEARCH held USING INDEX items_by_link (link_id=?)' <<<"$steps" || true)$(grep -c 'SCAN' <<<"$steps" || true)" "10"

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
run queue/enqueue_action ":producer='p'" ":collection='INBOX'" ":action='copy'" ":payload='{\"v\":1,\"seq\":6,\"to\":\"Archive-2026\"}'" ":target_collection='Archive-2026'" ":object_hash=NULL"
expect "overlay: a target reads the moves and copies queued into it in append order, never a row queued on it" \
    "$(run read/load_pending_arrivals ":collection='Archive-2026'" | cut -d'|' -f1,4,5 | tr '\n' ' ')$(run read/load_pending_arrivals ":collection='INBOX'" | wc -l)" \
    "1|INBOX|move 3|INBOX|copy 0"

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
expect "collection: the cascade counts its item as a purge, and the collection as one" "$(sql "SELECT purges FROM store_meta;")" "2"
collection Outbox
object "$m9"
run queue/pin_object ":hash='$m9'"
run queue/enqueue_action ":producer='p'" ":collection='Outbox'" ":action='submit'" ":payload='{\"v\":1,\"source\":\"smtp\",\"from\":\"alice@example.org\",\"rcpts\":[\"bob@example.org\"]}'" ":object_hash='$m9'"
run owner/park_action ":id=1" ":error='refused'"
expect "collection: a collection holding a parked action is not deleted" \
    "$(fails owner/delete_collection ":collection='Outbox'" && echo refused)|$(sql "SELECT count(*) FROM queue;")" "refused|1"
pin="$(run owner/cancel_action ":id=1")"
run owner/release_pins ":hashes='[\"$pin\"]'"
cursor="$(run read/load_change_cursor | cut -d'|' -f1,2)"
run owner/delete_collection ":collection='Outbox'"
expect "collection: once its actions are cancelled it is" "$(sql "SELECT count(*) FROM collections WHERE id = 'Outbox';")" "0"
# An empty collection takes no item whose purge would count, and a deleted
# row cannot be stamped (§4.5): collections_count_delete counts it, so a
# consumer of the feed reconciles its keys and learns the collection went.
expect "collection: deleting an empty collection draws no stamp and counts in purges" \
    "$(run read/load_change_cursor | cut -d'|' -f1,2)" "${cursor%|*}|$((${cursor#*|} + 1))"

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

# --- A parent and a presentation are what a source states (§14) ------------

fresh
collection INBOX work
collection Projects work
collection Q1 work
collection Other home
run owner/set_collection_parent ":collection='Projects'" ":parent='INBOX'"
run owner/set_collection_parent ":collection='Q1'" ":parent='Projects'"
expect "parent: the setter records it, and the reader lists it" \
    "$(run read/list_collections_by_account ":account='work'" | grep '^Q1|' | cut -d'|' -f5)" "Projects"
run owner/set_collection_parent ":collection='INBOX'" ":parent='Q1'"
expect "parent: a collection under its own child is refused, the row unchanged" \
    "$(sql "SELECT ifnull(parent, '-') FROM collections WHERE id = 'INBOX';")" "-"
run owner/set_collection_parent ":collection='INBOX'" ":parent='INBOX'"
expect "parent: a collection under itself is refused" \
    "$(sql "SELECT ifnull(parent, '-') FROM collections WHERE id = 'INBOX';")" "-"
run owner/set_collection_parent ":collection='Q1'" ":parent='Other'"
expect "parent: a parent of another account is refused, the row unchanged" \
    "$(sql "SELECT parent FROM collections WHERE id = 'Q1';")" "Projects"
run owner/set_collection_parent ":collection='Q1'" ":parent='Nowhere'"
expect "parent: an unknown parent is refused" \
    "$(sql "SELECT parent FROM collections WHERE id = 'Q1';")" "Projects"
cursor="$(run read/load_change_cursor | cut -d'|' -f1)"
run owner/set_collection_parent ":collection='Q1'" ":parent=NULL"
expect "parent: NULL moves it to the top, stamped in the feed" \
    "$(sql "SELECT ifnull(parent, '-') FROM collections WHERE id = 'Q1';")|$(run read/list_collections_changed_since ":since=$cursor" ":limit=10" | cut -d'|' -f1)" "-|Q1"
run owner/rename_collection ":collection='INBOX'" ":new_id='Inbox'"
expect "parent: a renamed parent is followed by its key" \
    "$(sql "SELECT parent FROM collections WHERE id = 'Projects';")" "Inbox"
run owner/delete_collection ":collection='Inbox'"
expect "parent: a deleted parent leaves its children at the top" \
    "$(sql "SELECT ifnull(parent, '-') FROM collections WHERE id = 'Projects';")" "-"
cursor="$(run read/load_change_cursor | cut -d'|' -f1)"
run owner/set_collection_presentation ":collection='Projects'" ":color='#3a87ad'" ":description='Work in flight'" ":sort_order=2"
run owner/set_collection_presentation ":collection='Q1'" ":color=NULL" ":description=NULL" ":sort_order=1"
expect "presentation: the setter records it, stamped in the feed" \
    "$(run read/list_collections_changed_since ":since=$cursor" ":limit=10" | cut -d'|' -f1 | sort | tr '\n' ' ')" "Projects Q1 "
expect "presentation: the reader lists it, ordered by sort_order" \
    "$(run read/list_collections_by_account ":account='work'" | cut -d'|' -f1,6,7,8 | tr '\n' ' ')" "Q1|||1 Projects|#3a87ad|Work in flight|2 "
run owner/set_collection_presentation ":collection='Projects'" ":color=NULL" ":description=NULL" ":sort_order=NULL"
expect "presentation: a source stating none clears it" \
    "$(sql "SELECT count(*) FROM collections WHERE id = 'Projects' AND (color IS NOT NULL OR description IS NOT NULL OR sort_order IS NOT NULL);")" "0"
run owner/set_collection_presentation ":collection='Nowhere'" ":color='red'" ":description=NULL" ":sort_order=NULL"
expect "presentation: an undeclared collection is not declared by it" \
    "$(sql "SELECT count(*) FROM collections WHERE id = 'Nowhere';")" "0"

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
sql "INSERT INTO bindings(item, collection, source, handle, base_present) VALUES((SELECT id FROM items WHERE collection = 'INBOX' AND link_id = 'a'), 'INBOX', 'graph', '1', 1);"
expect "capability: an item answers for the sources binding it alone, each holding it" \
    "$(run read/load_item_capabilities ":collection='INBOX'" ":seq=1" | tr '\n' ' ')" "graph|mail.message.remove|full||1 "
item INBOX b 2
item INBOX c 3
sql "INSERT INTO bindings(item, collection, source, handle) VALUES((SELECT id FROM items WHERE collection = 'INBOX' AND link_id = 'b'), 'INBOX', 'graph', char(1) || 'b');
     INSERT INTO bindings(item, collection, source, handle, base_present) VALUES((SELECT id FROM items WHERE collection = 'INBOX' AND link_id = 'c'), 'INBOX', 'graph', char(1) || 'c', 1);"
expect "capability: a pending create is bound unheld, its server holding nothing yet, a delivered one held" \
    "$(run read/load_item_capabilities ":collection='INBOX'" ":seq=2" | cut -d'|' -f1,5)|$(run read/load_item_capabilities ":collection='INBOX'" ":seq=3" | cut -d'|' -f1,5)" "graph|0|graph|1"
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

# --- A row the owner does not know stays pending, untouched (§15.2, §15.4) ---
# Skipping is not parking: a known action at a v the owner does not know, an
# action it does not know and an application's own are left as they were
# enqueued, error NULL and attempts 0, while the rows behind them apply; the
# drain lists them again in append order, and a reader overlaying the
# collection still lists them.

fresh
collection INBOX
item INBOX mid:a 1
item INBOX mid:b 2
# An unknown payload: a known action at a v this draft does not define.
run queue/enqueue_action ":producer='p'" ":collection='INBOX'" ":action='remove'" ":payload='{\"v\":2,\"seq\":1}'" ":target_collection=NULL" ":object_hash=NULL"
# An unknown payload: an action this draft does not define.
run queue/enqueue_action ":producer='p'" ":collection='INBOX'" ":action='snooze'" ":payload='{\"v\":1,\"seq\":1,\"until\":\"2026-12-01T09:00:00Z\"}'" ":target_collection=NULL" ":object_hash=NULL"
# An unknown payload: an application's own action.
run queue/enqueue_action ":producer='p'" ":collection='INBOX'" ":action='x-archive'" ":payload='{\"v\":1,\"seq\":1}'" ":target_collection=NULL" ":object_hash=NULL"
run queue/enqueue_action ":producer='p'" ":collection='INBOX'" ":action='set-flags'" ":payload='{\"v\":1,\"seq\":2,\"flags\":[\"\\\\Seen\"],\"base\":[]}'" ":target_collection=NULL" ":object_hash=NULL"
run queue/enqueue_action ":producer='p'" ":collection='INBOX'" ":action='remove'" ":payload='{\"v\":1,\"seq\":2}'" ":target_collection=NULL" ":object_hash=NULL"
unknown_before="$(sql "SELECT id, action, payload, attempts, error IS NULL, created_at FROM queue WHERE id <= 3 ORDER BY id;")"
expect "skip: the drain lists the three rows it does not know before the two it does, in append order" \
    "$(run owner/list_pending_actions | cut -d'|' -f1,5,9 | tr '\n' ' ')" "1|remove|0 2|snooze|0 3|x-archive|0 4|set-flags|0 5|remove|0 "
for id in 4 5; do
    run owner/claim_action ":id=$id" >/dev/null
    run owner/record_receipt ":id=$id" ":collection='INBOX'" ":seq=NULL"
done
expect "skip: the rows behind a skipped one apply, each leaving its receipt" \
    "$(run read/load_receipt ":id=4" | cut -d'|' -f2)$(run read/load_receipt ":id=5" | cut -d'|' -f2)$(run read/load_action ":id=4")$(run read/load_action ":id=5")" "INBOXINBOX"
expect "skip: a skipped row is as it was enqueued, its payload, attempts and error untouched" \
    "$(sql "SELECT id, action, payload, attempts, error IS NULL, created_at FROM queue WHERE id <= 3 ORDER BY id;")" "$unknown_before"
expect "skip: each stays pending and unparked, a v 2 of a known action, an unknown action and an x- one alike" \
    "$(for id in 1 2 3; do run read/load_action ":id=$id" | cut -d'|' -f1,5,8,9; done | tr '\n' ' ')$(run owner/load_parked_actions | wc -l)" \
    "1|remove|0| 2|snooze|0| 3|x-archive|0| 0"
expect "skip: the next drain lists them again, and nothing else" \
    "$(run owner/list_pending_actions | cut -d'|' -f1,5,9 | tr '\n' ' ')" "1|remove|0 2|snooze|0 3|x-archive|0 "
expect "skip: a reader overlaying the collection still lists them, with the payload it cannot fold" \
    "$(run read/load_pending_actions ":collection='INBOX'" | cut -d'|' -f1,4,5,8 | tr '\n' ' ')" \
    "1|remove|{\"v\":2,\"seq\":1}|0 2|snooze|{\"v\":1,\"seq\":1,\"until\":\"2026-12-01T09:00:00Z\"}|0 3|x-archive|{\"v\":1,\"seq\":1}|0 "

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
# A receipt outlives the collection its row was queued on (§15.4): the delete
# a `collection-delete` asked for, or any other, leaves it naming no
# collection, so the intent still reads as performed, never as withdrawn.
run owner/delete_collection ":collection='INBOX'"
expect "receipt: its collection deleted, a receipt stays and names none; another collection's is untouched" \
    "$(run read/load_receipt ":id=1" ".nullvalue=NULL" | cut -d'|' -f2,3)|$(run read/load_receipt ":id=3" | cut -d'|' -f2)" "NULL|NULL|Sent"


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
run owner/upsert_mail_summary ":collection='INBOX'" ":link_id='m@example.org'" ":message_id='m@example.org'" ":subject='Notice'" \
    ":sender='cron@x'" ":sender_name=NULL" ":date='2026-08-01T10:00:00Z'" ":size=10" ":attachment=NULL" ":invitation=NULL"
# shares <collection> <link_id> [subject sender date]: the seq a member being
# named there shares, its summary's subject, sender and date NULL when unstated.
shares() {
    run owner/seq_for_link_any ":collection='$1'" ":link_id='$2'" ":subject=${3:-NULL}" ":sender=${4:-NULL}" ":date=${5:-NULL}"
}
expect "seq: a Message-ID spelling an event's UID is another item, drawing its own seq" \
    "$(shares INBOX 'x@example.org' "''" NULL NULL)" ""
expect "seq: a message filed twice shares one, retained or not, and so does a part's file in two folders" \
    "$(shares Archive 'm@example.org' "'Notice'" "'cron@x'" "'2026-08-01T10:00:00Z'")|$(shares Folder 'part:m@example.org#2')|$(shares Cal 'part:m@example.org#2')" \
    "2|3|"
# The agreement of §9 guards the shared seq across collections: a message
# stating another subject, date or sender under the Message-ID is another one,
# and draws its own, as one meeting a row with no summary does. The three are
# read for mail alone.
expect "seq: a message disagreeing with the row holding its Message-ID elsewhere, on its subject, its date or its sender, shares no seq" \
    "$(shares Archive 'm@example.org' "'notice'" "'cron@x'" "'2026-08-01T10:00:00Z'")|$(shares Archive 'm@example.org' "'Notice'" "'cron@x'" "'2026-08-02T10:00:00Z'")|$(shares Archive 'm@example.org' "'Notice'" "'dan@x'" "'2026-08-01T10:00:00Z'")|$(shares Archive 'm@example.org' "'Notice'" NULL "'2026-08-01T10:00:00Z'")" \
    "|||"
item Archive 'bare@example.org' 4
expect "seq: a message meeting a row that states no summary shares none, another kind's row needing none" \
    "$(shares INBOX 'bare@example.org' "''" NULL NULL)|$(shares Folder 'part:m@example.org#2' "'x'" "'y'" "'z'")" "|3"
run owner/upsert_mail_summary ":collection='Archive'" ":link_id='bare@example.org'" ":message_id='bare@example.org'" ":subject=''" \
    ":sender=NULL" ":sender_name=NULL" ":date=NULL" ":size=NULL" ":attachment=NULL" ":invitation=NULL"
expect "seq: an unknown date and sender match unknown ones, a NULL size playing no part" \
    "$(shares INBOX 'bare@example.org' "''" NULL NULL)" "4"
# Rows that agree with the member may hold several seqs once a summary was
# restated after its seq was drawn: the lowest is shared, whatever the order
# the rows are read in.
item Archive 'm@example.org' 9
run owner/upsert_mail_summary ":collection='Archive'" ":link_id='m@example.org'" ":message_id='m@example.org'" ":subject='Notice'" \
    ":sender='cron@x'" ":sender_name=NULL" ":date='2026-08-01T10:00:00Z'" ":size=NULL" ":attachment=NULL" ":invitation=NULL"
run owner/set_collection_kind ":collection='Sent'" ":account=NULL" ":kind='message/rfc822'"
expect "seq: of several rows that agree, the lowest seq is shared" \
    "$(shares Sent 'm@example.org' "'Notice'" "'cron@x'" "'2026-08-01T10:00:00Z'")" "2"
steps="$(plan owner/seq_for_link_any ":collection='INBOX'" ":link_id='x@example.org'" ":subject=''" ":sender=NULL" ":date=NULL")"
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
        ":subject='s $2'" ":sender='alice@example.org'" ":sender_name='Alice'" \
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
expect "narrowed: a narrowed one handing no enumeration finds none absent, a filter's silence proving nothing" \
    "$(run owner/list_unstamped_bindings ":collection='INBOX'" ":source='imap'" ":narrowed=1" ":enumerated=0" | tr '\n' ' ')" ""
expect "narrowed: an unfiltered enumeration of handles finds absent what it lacks, whatever its date" \
    "$(run owner/list_unstamped_bindings ":collection='INBOX'" ":source='imap'" ":narrowed=1" ":enumerated=1" ":handles='[\"20\"]'" | tr '\n' ' ')" "30|recent 40|future "
expect "narrowed: a member the enumeration holds is never absent, dated before the round opened included" \
    "$(run owner/list_unstamped_bindings ":collection='INBOX'" ":source='imap'" ":narrowed=1" ":enumerated=1" ":handles='[\"30\"]'" | tr '\n' ' ')" "20|nodate 40|future "
mail INBOX resent 4 50 "'2026-01-01T00:00:00Z'"
run owner/open_round ":collection='INBOX'" ":source='imap'" ":since=NULL" ":until='2026-09-01T00:00:00Z'" ":band=1"
expect "narrowed: a band whose upper bound read the arrival keeps an old-dated member its enumeration holds" \
    "$(run owner/list_unstamped_bindings ":collection='INBOX'" ":source='imap'" ":narrowed=1" ":enumerated=1" ":handles='[\"30\",\"50\"]'" | tr '\n' ' ')|$(run owner/list_unstamped_bindings ":collection='INBOX'" ":source='imap'" ":narrowed=1" ":enumerated=1" ":handles='[\"30\"]'" | tr '\n' ' ')" "|50|resent "

# --- Evicting below a date is manual and pushes nothing (§11.3) -------------

fresh
collection INBOX
collection Archive
object "$h1"
mail INBOX old 1 10 "'2026-08-01T10:00:00Z'"
sql "UPDATE items SET object = (SELECT id FROM objects WHERE hash = '$h1') WHERE link_id = 'old'; UPDATE bindings SET base_object = (SELECT id FROM objects WHERE hash = '$h1') WHERE item IN (SELECT id FROM items WHERE link_id = 'old');"
mail INBOX dirty 2 11 "'2026-08-01T10:00:00Z'" '["\\Flagged"]' '[]'
mail INBOX recent 3 12 "'2026-10-06T08:00:00Z'"
mail INBOX nodate 4 13 NULL
mail Archive old 1 10 "'2026-08-01T10:00:00Z'"
# Both directions of the keyword comparison: an item holding a keyword its
# base lacks, or lacking one its base holds, or naming another of the same
# number, holds an unpushed flag change and stays; the same keyword on both
# sides owes nothing.
mail INBOX labelled 30 30 "'2026-08-01T10:00:00Z'" '["$todo"]' '[]'
mail INBOX unlabelled 31 31 "'2026-08-01T10:00:00Z'" '[]' '["$todo"]'
mail INBOX settled 32 32 "'2026-08-01T10:00:00Z'" '["$todo","\\Seen"]' '["\\Seen","$todo"]'
mail INBOX relabelled 33 33 "'2026-08-01T10:00:00Z'" '["$todo"]' '["$done"]'
sql "INSERT INTO items(collection, link_id, seq, flags_known, level) VALUES('INBOX', 'created', 5, 1, 2);
     INSERT INTO bindings(item, collection, source, handle) VALUES((SELECT id FROM items WHERE collection = 'INBOX' AND link_id = 'created'), 'INBOX', 'imap', char(1) || 'created');
     INSERT INTO mail_summary(item, subject, date) VALUES((SELECT id FROM items WHERE collection = 'INBOX' AND link_id = 'created'), '', '2026-08-01T10:00:00Z');"
# A delivered create (SYNC.md §2, §5): based under its provisional handle, its
# base naming nothing, \Seen staged on it since. No listing has named its
# member, so nothing relists it and what was staged on it is owed to the page
# that lands it: it stays, though no flag set differs and its base is present.
sql "INSERT INTO items(collection, link_id, seq, flags_known, marks, level) VALUES('INBOX', 'delivered', 34, 1, 1, 1);
     INSERT INTO bindings(item, collection, source, handle, base_present) VALUES((SELECT id FROM items WHERE collection = 'INBOX' AND link_id = 'delivered'), 'INBOX', 'imap', char(1) || 'delivered', 1);
     INSERT INTO mail_summary(item, subject, date) VALUES((SELECT id FROM items WHERE collection = 'INBOX' AND link_id = 'delivered'), '', '2026-08-01T10:00:00Z');"
run owner/recompute_refcounts
purges="$(sql "SELECT purges FROM store_meta;")"
expect "evict: only what owes nothing, below the date, in the collection" \
    "$(run owner/evict_before ":collection='INBOX'" ":before='2026-09-01T00:00:00Z'" | sort -n | tr '\n' ' ')" "1 32 "
run owner/recompute_refcounts
expect "evict: an unpushed flag, a keyword on the item alone, on the base alone or exchanged for another, a pending create, a delivered one waiting for its arrival, the undated and the newer stay" \
    "$(sql "SELECT link_id FROM items WHERE collection = 'INBOX' ORDER BY link_id;" | tr '\n' ' ')" "created delivered dirty labelled nodate recent relabelled unlabelled "
expect "evict: bindings, summary and addresses go with the item" \
    "$(sql "SELECT (SELECT count(*) FROM bindings WHERE collection = 'INBOX' AND item IN (SELECT id FROM items WHERE link_id = 'old')) + (SELECT count(*) FROM mail_summary WHERE item IN (SELECT id FROM items WHERE collection = 'INBOX' AND link_id = 'old'));")" "0"
expect "evict: the body is released to the collector, the holder elsewhere untouched" \
    "$(sql "SELECT refcount FROM objects WHERE hash = '$h1';")$(sql "SELECT count(*) FROM items WHERE collection = 'Archive';")" "01"
expect "evict: no tombstone, no queued push, and the feed counts a purge" \
    "$(sql "SELECT count(*) FROM items WHERE deleted = 1;")$(sql "SELECT count(*) FROM queue;")$(sql "SELECT purges FROM store_meta;")" "00$((purges + 2))"
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
expect "evict: a mail a person's reference names, from either end, stays; a rule's reference does not hold one" \
    "$(run owner/evict_before ":collection='INBOX'" ":before='2026-09-01T00:00:00Z'")|$(sql "SELECT count(*) FROM item_reference WHERE origin = 'user';")" "7|2"
# A mail no source binds is the store's alone (a copy kept on the device):
# no relisting restores it, so it owes its own keeping (§11.3).
sql "INSERT INTO items(collection, link_id, seq, flags_known, object, level) VALUES('INBOX', 'local', 9, 1, (SELECT id FROM objects WHERE hash = '$h1'), 2);
     INSERT INTO mail_summary(item, subject, date) VALUES((SELECT id FROM items WHERE collection = 'INBOX' AND link_id = 'local'), 'kept here', '2026-08-01T10:00:00Z');"
expect "evict: a mail no source binds stays, no relisting restoring it" \
    "$(run owner/evict_before ":collection='INBOX'" ":before='2026-09-01T00:00:00Z'")|$(sql "SELECT count(*) FROM items WHERE link_id = 'local';")" "|1"

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
     UPDATE items SET object = (SELECT id FROM objects WHERE hash = CASE link_id WHEN 'old' THEN '$h1' WHEN 'dirty' THEN '$h2' WHEN 'nodate' THEN '$h3' WHEN 'recent' THEN '$h4'
         WHEN 'conflicted' THEN '$h5' WHEN 'diverged' THEN '$h6' WHEN 'edited' THEN '$h7' WHEN 'witness' THEN '$h8' ELSE '$h9' END);
     UPDATE bindings SET base_object = (SELECT object FROM items i WHERE i.id = bindings.item),
         shared_object = (SELECT object FROM items i WHERE i.id = bindings.item);
     UPDATE items SET conflicted = 1, conflict_object = (SELECT id FROM objects WHERE hash = '$hc') WHERE link_id = 'conflicted';
     UPDATE bindings SET conflicted = 1 WHERE item IN (SELECT id FROM items WHERE link_id = 'diverged');
     UPDATE bindings SET base_object = (SELECT id FROM objects WHERE hash = '$h1') WHERE item IN (SELECT id FROM items WHERE link_id = 'edited');
     UPDATE items SET deleted = 1 WHERE link_id = 'gone';
     INSERT INTO items(collection, link_id, seq, flags_known, object, sort_key, level) VALUES
         ('INBOX', 'created', 20, 1, (SELECT id FROM objects WHERE hash = '$h9'), '2026-08-01T10:00:00Z', 2),
         ('INBOX', 'lone', 21, 1, (SELECT id FROM objects WHERE hash = '$h9'), '2026-08-01T10:00:00Z', 2),
         ('Cards', 'card', 22, 0, (SELECT id FROM objects WHERE hash = '$h9'), '2026-08-01', 2);
     INSERT INTO bindings(item, collection, source, handle) VALUES((SELECT id FROM items WHERE collection = 'INBOX' AND link_id = 'created'), 'INBOX', 'imap', char(1) || 'created');
     INSERT INTO bindings(item, collection, source, handle, base_present, base_object) VALUES((SELECT id FROM items WHERE collection = 'Cards' AND link_id = 'card'), 'Cards', 'dav', 'c', 1, (SELECT id FROM objects WHERE hash = '$h9'));
     INSERT INTO bindings(item, collection, source, handle, base_flags_known, base_object, base_present)
         VALUES((SELECT id FROM items WHERE collection = 'Both' AND link_id = 'full'), 'Both', 'graph', 'g20', 1, (SELECT id FROM objects WHERE hash = '$h9'), 1);
     INSERT INTO sources(collection, source) VALUES('Both', 'imap'), ('Both', 'graph');"
# A base is present iff base_present is 1 (§13): no other base column states
# one without it, so `witness`, based like the rest, cannot be made a pending
# create that still names a base body, a base revision or a known flag set.
expect "base: a binding naming a base body, a revision or a known base flag set without base_present is refused" \
    "$(for mixed in "base_flags_known = 0" "base_flags_known = 0, base_object = NULL, base_revision = 'r1'" "base_object = NULL"; do
           sql "UPDATE bindings SET base_present = 0, $mixed WHERE item IN (SELECT id FROM items WHERE link_id = 'witness');" 2>&1 | grep -c 'CHECK constraint failed: base_present = 1' || true
       done | tr -d '\n')" "111"
run owner/recompute_refcounts
cursor="$(run read/load_change_cursor | cut -d'|' -f1)"
set=":collections='[\"INBOX\",\"Both\",\"Cards\"]'"
run owner/release_bases_before "$set" ":before='2026-09-01T00:00:00Z'"
expect "release: below the date, what needs no body, the undated included, two sources' bases alike" \
    "$(run owner/release_before "$set" ":before='2026-09-01T00:00:00Z'" | sort -n | tr '\n' ' ')" "1 2 3 8 9 "
run owner/recompute_refcounts
expect "release: a conflict, a diverged binding, a local edit, a pending create, no binding, an unbound source, another kind, a tombstone, the newer and an unnamed collection keep theirs" \
    "$(sql "SELECT collection || ':' || link_id FROM items WHERE object IS NOT NULL ORDER BY collection, link_id;" | tr '\n' ' ')" \
    "Archive:old Both:half Cards:card INBOX:conflicted INBOX:created INBOX:diverged INBOX:edited INBOX:gone INBOX:lone INBOX:recent "
expect "release: a tombstone, a newer item, a conflicted one and another kind keep their bases" \
    "$(sql "SELECT count(*) FROM bindings WHERE item IN (SELECT id FROM items WHERE link_id IN ('gone', 'recent', 'conflicted', 'card')) AND base_object IS NOT NULL;")|$(sql "SELECT o.hash FROM items i JOIN objects o ON o.id = i.object WHERE i.link_id = 'gone';")" "4|$h9"
expect "release: back to Meta, flags, summary and addresses kept" \
    "$(sql "SELECT level, flags_known FROM items WHERE collection = 'INBOX' AND link_id = 'dirty';")|$(flags INBOX dirty)|$(sql "SELECT count(*) FROM mail_summary WHERE item IN (SELECT id FROM items WHERE collection = 'INBOX') AND item IN (SELECT id FROM items WHERE link_id IN ('old', 'dirty', 'nodate', 'witness'));")" \
    '1|1|\Flagged|4'
expect "release: a shared body naming the released body lets go of it, another stays" \
    "$(sql "SELECT count(*) FROM bindings WHERE item IN (SELECT id FROM items WHERE link_id IN ('old', 'dirty', 'nodate', 'witness')) AND collection = 'INBOX' AND shared_object IS NULL;")|$(sql "SELECT o.hash FROM bindings b JOIN objects o ON o.id = b.shared_object WHERE b.item IN (SELECT id FROM items WHERE link_id = 'edited');")" "4|$h7"
expect "release: the bases let go of the body, every binding still based, its flags kept" \
    "$(sql "SELECT count(*) FROM bindings WHERE item IN (SELECT id FROM items WHERE link_id IN ('old', 'dirty', 'nodate', 'witness', 'full')) AND collection != 'Archive' AND base_object IS NULL AND base_present = 1;")|$(sql "SELECT base_flags_known FROM bindings WHERE item IN (SELECT id FROM items WHERE link_id = 'dirty');")|$(base_flags INBOX dirty imap)" \
    "6|1|"
expect "release: a body held elsewhere stays pinned, the rest fall to the collector" \
    "$(run owner/list_garbage_objects | sort | tr '\n' ' ')|$(sql "SELECT refcount FROM objects WHERE hash = '$h1';")" "$h2 $h3 $h8 |4"
expect "release: each released item moves in the feed" \
    "$(run read/list_items_changed_since ":since=$cursor" ":limit=10" | cut -d'|' -f3 | sort -n | tr '\n' ' ')" "1 2 3 8 9 "
expect "release: a second run finds nothing" \
    "$(run owner/release_bases_before "$set" ":before='2026-09-01T00:00:00Z'")$(run owner/release_before "$set" ":before='2026-09-01T00:00:00Z'")" ""
run owner/release_bases_before "$set" ":before=NULL"
expect "release: no ceiling reaches the newest" \
    "$(run owner/release_before "$set" ":before=NULL")" "4"

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
sql "UPDATE items SET deleted = 1, retained_at = '2026-10-01T00:00:00.000Z' WHERE collection = 'Archive' AND link_id = 'm';"
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
run owner/upsert_mail_summary ":collection='INBOX'" ":link_id='m4'" ":message_id='m4'" \
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
        ":until=NULL" ":priority=NULL" ":parent=$3" ":mid=$4"
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
        ":until=NULL" ":priority=10" ":parent=NULL" ":mid=NULL" && echo refused)" "refused"

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
    "$(sql "SELECT group_concat(collection) FROM items WHERE link_id = 'part:m#3' AND (deleted = 0 OR object IS NOT NULL);")" "work/Docs,work/INBOX"
for target in local synced; do
    ref $mail_kind m $file_kind $target related user >/dev/null
    run owner/remove_reference ":from_kind='$mail_kind'" ":from_link_id='m'" ":to_kind='$file_kind'" ":to_link_id='$target'" ":role='related'" >/dev/null
done
expect "file: a file holding a body, or bound by a source, is never collected for want of a reference" \
    "$(sql "SELECT link_id FROM items WHERE link_id IN ('local', 'synced') ORDER BY link_id;" | tr '\n' ' ')" "local synced "
sql "UPDATE items SET deleted = 1, retained_at = '2026-10-01T00:00:00.000Z' WHERE link_id = 'm';"
run owner/purge_item ":collection='work/INBOX'" ":seq=1" >/dev/null
expect "file: the message's last row gone, its stand-in goes and the saved copy stays with its body" \
    "$(sql "SELECT i.collection || ':' || ifnull(o.hash, '') FROM items i LEFT JOIN objects o ON o.id = i.object WHERE i.link_id = 'part:m#2';")|$(sql "SELECT count(*) FROM item_reference;")" \
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
    "$(flags Local note)|$(sql "SELECT changed > $before FROM items WHERE link_id = 'note';")|$(sql "SELECT i.deleted, i.retained_at IS NOT NULL, o.hash FROM items i LEFT JOIN objects o ON o.id = i.object WHERE i.link_id = 'gone';")|$(run read/count_retained ":collection='Local'")" \
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
# Every engine load runs both reads (SYNC.md §10) and supersessions is nearly
# always empty: each starts there and reaches its items by their key, never
# through the collection's items.
for statement in list_superseded_bindings list_superseded_pending; do
    steps="$(plan "owner/$statement" ":collection='tasks-b'" ":source='caldav'")"
    expect "supersedes: $statement starts from supersessions and seeks each item by its key, walking no collection" \
        "$(grep -c 'SCAN s\b' <<<"$steps" || true)$(grep -cE 'SEARCH [nt] USING INTEGER PRIMARY KEY \(rowid=\?\)' <<<"$steps" || true)$(grep -cE '(SCAN|SEARCH) [nt] .*(collection|SCAN [nt]$)|SCAN [nt]$' <<<"$steps" || true)" "120"
done

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

# reply <link_id> <position> <message_id>: one In-Reply-To id of a mail.
reply() {
    run owner/insert_in_reply_to ":collection='$(sql "SELECT collection FROM items WHERE link_id = '$1';")'" \
        ":link_id='$1'" ":position=$2" ":message_id='$3'"
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
    ":priority=NULL" ":parent=NULL" ":mid=NULL"
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

# The format version a new store records, read off init_store_meta: this
# part's own, which checks/names.sh holds to STORAGE.md's Status line, a
# draft's name while the part is a draft and storage-vN once it is released,
# so the scenarios below follow the part across its release unedited.
own_format="$(grep -o "'storage-[a-z0-9-]*'" "$root/queries/storage/owner/init_store_meta.sql" | tr -d "'")"

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
expect "format: init_store_meta stamps this part's version, version 1 with both compatibility versions, BLAKE3 and the creator's revision" \
    "$(run read/load_store_meta | cut -d'|' -f1,2,3,8,9,10,11)" "pimdir|1|blake3|3|$own_format|1|1"
case "$own_format" in
    storage-draft-*)
        expect "format: a draft's store opens under that draft alone, never under another nor a release" \
            "$(opens "$own_format") $(opens storage-draft-14) $(opens storage-draft-99) $(opens storage-v1)" \
            "opened refused refused refused" ;;
    *)
        expect "format: a released store opens under its release, and under no draft" \
            "$(opens "$own_format") $(opens storage-draft-15) $(opens storage-draft-99)" \
            "opened refused refused" ;;
esac
sql "ALTER TABLE store_meta DROP COLUMN format_version;"
expect "format: a store an earlier draft wrote lacks the marker, so load_store_meta fails and it is refused" \
    "$(fails read/load_store_meta && echo failed) $(opens "$own_format")" "failed refused"

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

# --- A released store above a program's version is judged by store_meta (§4.2)

# released <profile> <own version>: the judgement a released program of that
# schema version makes of the store (§4.2, §6 step 2), from six columns of
# store_meta and PRAGMA user_version, and from nothing else of the schema: the
# format, the format version (storage-v and the version, never a draft's
# name), the version against user_version, the algorithm, and the
# compatibility version of its profile. An owner opens a version it knows.
released() {
    local profile="$1" own="$2" meta format version algo format_version read produce
    meta="$(run read/load_store_meta 2>/dev/null)" || { echo refused; return; }
    IFS='|' read -r format version algo _ _ _ _ _ format_version read produce _ <<<"$meta"
    if [ "$format" != pimdir ] || [ "$format_version" != "storage-v$version" ] || [ "$algo" != blake3 ] \
        || [ "$version" != "$(sql "PRAGMA user_version;")" ]; then
        echo refused
        return
    fi
    case "$profile" in
        reader) [ "$read" -le "$own" ] ;;
        producer) [ "$read" -le "$own" ] && [ "$produce" -le "$own" ] ;;
        owner) [ "$version" -le "$own" ] ;;
    esac && echo opened || echo refused
}
# judged <own version>: the three profiles' judgements, in order.
judged() {
    echo "$(released reader "$1") $(released producer "$1") $(released owner "$1")"
}

# A synthetic version 2 store: a table, an index, a column, a trigger and a
# view version 1 does not know, stamped as its migration states.
fresh
collection INBOX
item INBOX a 1
sql "UPDATE store_meta SET format_version = 'storage-draft-15';"
expect "released: a released program refuses a draft's store, whatever its profile" "$(judged 1)" "refused refused refused"
sql "CREATE TABLE x_later (id INTEGER PRIMARY KEY, note TEXT);
     CREATE INDEX x_items_by_level ON items(level);
     ALTER TABLE collections ADD COLUMN x_icon TEXT;
     CREATE TRIGGER x_later_counts AFTER INSERT ON x_later BEGIN UPDATE x_later SET note = 'seen' WHERE id = NEW.id; END;
     CREATE VIEW x_live AS SELECT collection, link_id FROM items WHERE deleted = 0;
     PRAGMA user_version = 2;"
run owner/set_store_version ":version=2" ":read_version=1" ":produce_version=1"
expect "released: a version 2 store raising neither opens for a version 1 reader and producer, and no version 1 owner" \
    "$(judged 1)" "opened opened refused"
expect "released: what version 2 added is no damage, a version 1 reader's statements answering the rows they answered" \
    "$(run read/list_collections | cut -d'|' -f1)|$(run read/count_items ":collection='INBOX'")|$(run read/load_change_cursor | awk -F'|' '{ print NF }')" "INBOX|1|4"
run owner/set_store_version ":version=2" ":read_version=2" ":produce_version=1"
expect "released: one raising read_version is refused by every version 1 program" "$(judged 1)" "refused refused refused"
run owner/set_store_version ":version=2" ":read_version=1" ":produce_version=2"
expect "released: one raising produce_version opens for a version 1 reader alone" "$(judged 1)" "opened refused refused"
run owner/set_store_version ":version=2" ":read_version=2" ":produce_version=2"
expect "released: a version 2 program opens it under every profile" "$(judged 2)" "opened opened opened"
sql "PRAGMA user_version = 3;"
expect "released: a store whose version disagrees with user_version is corrupt, and refused" "$(judged 3)" "refused refused refused"
sql "PRAGMA user_version = 2; UPDATE store_meta SET format_version = 'storage-draft-15';"
expect "released: a draft's name over a later version is refused all the same" "$(judged 2)" "refused refused refused"

# --- A migration keeps every row; one rebuilding a table owes more (§6) ----

# The rehearsal migrations of checks/rehearsal/, which never ship: an
# additive one, a rebuild of collections and of queue with foreign keys off
# before the transaction, the edit of a CHECK under writable_schema, and the
# rebuild as step 3 runs any other migration, which loses every referencing
# row and is forbidden. checks/floor.sh runs the same on SQLite 3.18.2.
if ! bash "$rehearsal/run.sh" "$root" sqlite3; then
    failures=$((failures + 1))
fi

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
sql "UPDATE items SET object = (SELECT id FROM objects WHERE hash = '$hb') WHERE link_id = 'held';"
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
run owner/set_sync_version ":sync_version='sync-draft-15'"
expect "sync: set_sync_version records the engine's version, and nothing else moves" \
    "$(run read/load_store_meta | cut -d'|' -f9,14)" "$own_format|sync-draft-15"
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
cp "$dir/backup.db" "$dir/backup-again.db"
cp "$dir/backup.db" "$dir/backup-once-more.db"
item INBOX b 2
# The store went on after the backup and is itself a restored copy by now, so
# its incarnation is above the backup's own.
run owner/raise_incarnation ":replaced=NULL"
recorded="$(run read/load_change_cursor)"
# The restore: the copy takes the store's place and is raised past both
# incarnations before anything opens it.
mv "$dir/backup.db" "$dir/pimdir.db"
copied="$(run read/load_change_cursor | cut -d'|' -f4)"
run owner/raise_incarnation ":replaced=$(cut -d'|' -f4 <<< "$recorded")"
restored="$(run read/load_change_cursor)"
expect "restore: the copy keeps the id, answers an incarnation above its own and the replaced store's, and a stamp below the one a consumer recorded" \
    "$([ "$(cut -d'|' -f3 <<< "$restored")" = "$id" ] && echo same)|$copied|$([ "$(cut -d'|' -f4 <<< "$restored")" -gt "$(cut -d'|' -f4 <<< "$recorded")" ] && [ "$(cut -d'|' -f4 <<< "$recorded")" -gt "$copied" ] && echo above)|$([ "$(cut -d'|' -f1 <<< "$restored")" -lt "$(cut -d'|' -f1 <<< "$recorded")" ] && echo below)" \
    "same|1|above|below"
# The same backup restored twice more, the replaced store unreadable each
# time: each copy is raised above its own incarnation, and by a random
# stride, so the two answer different incarnations and a consumer of one
# never takes the other for it.
mv "$dir/backup-again.db" "$dir/pimdir.db"
run owner/raise_incarnation ":replaced=NULL"
again="$(run read/load_change_cursor | cut -d'|' -f4)"
mv "$dir/backup-once-more.db" "$dir/pimdir.db"
run owner/raise_incarnation ":replaced=NULL"
once_more="$(run read/load_change_cursor | cut -d'|' -f4)"
expect "restore: two restores of one backup, the replaced store unread, are raised above the copy's own incarnation and answer different ones" \
    "$([ "$again" -gt "$copied" ] && [ "$once_more" -gt "$copied" ] && echo above)|$([ "$again" != "$once_more" ] && [ "$again" != "$(cut -d'|' -f4 <<< "$restored")" ] && [ "$once_more" != "$(cut -d'|' -f4 <<< "$restored")" ] && echo different)" \
    "above|different"
expect "identity: the id never changes and the incarnation never goes down" \
    "$(sql "UPDATE store_meta SET store_id = '00000000000000000000000000000000';" 2>&1 | grep -c 'store identity is fixed')$(sql "UPDATE store_meta SET incarnation = $copied;" 2>&1 | grep -c 'store identity is fixed')|$(run read/load_change_cursor | cut -d'|' -f3,4)" \
    "11|$id|$once_more"
# The mode is the restore's to set (§8): the copy of a WAL database is made
# in a rollback journal mode, whatever the store it was taken from ran in.
sqlite3 "$dir/wal.db" "PRAGMA journal_mode = WAL; CREATE TABLE t(x); VACUUM INTO '$dir/wal-copy.db';" > /dev/null
expect "restore: a copy made by VACUUM INTO of a WAL database carries no WAL mode, so the restore puts it in the mode of the store it replaces" \
    "$(sqlite3 "$dir/wal.db" 'PRAGMA journal_mode;')|$(sqlite3 "$dir/wal-copy.db" 'PRAGMA journal_mode;')" "wal|delete"

# --- Column types are held by the schema (§4.1) -----------------------------

fresh
collection INBOX
expect "types: a value of another type is refused where STRICT refused it, a NULL key and a text checkpoint included" \
    "$(for value in "'$h1', 'big'" "'$h1', 1.5" "CAST('$h1' AS BLOB), 1" "NULL, 1"; do sql "INSERT INTO objects(hash, size) VALUES($value);" 2>&1 | grep -ci error; done | tr -d '\n')$(sql "INSERT INTO sources(collection, source, checkpoint) VALUES('INBOX', 's', 'text');" 2>&1 | grep -ci error)" \
    "11111"
expect "types: a value SQLite converts losslessly is kept, converted" \
    "$(sql "INSERT INTO objects(hash, size) VALUES('$h1', '7'); INSERT INTO items(collection, link_id, seq, level) VALUES('INBOX', 5, 1, 2.0);
            SELECT typeof(size) FROM objects; SELECT typeof(link_id) || typeof(level) FROM items;" | tr '\n' ' ')" "integer textinteger "

# --- Shapes are held by the schema (§13) -------------------------------------

# One row of each table whose shapes §13 fixes, written as the statements
# write them, then one write per shape a statement of an implementation's own
# could get wrong: each is refused by the CHECK naming its column, and the
# rows stay as they were. checks/floor.sh runs the same writes on the floor.
fresh
collection INBOX
object "$h1"
item INBOX a 1
run owner/insert_binding ":collection='INBOX'" ":link_id='a'" ":source='imap'" ":handle='10'" \
    ":base_flags='[]'" ":base_object=NULL" ":base_revision=NULL" ":base_present=1" \
    ":conflicted=0" ":conflict_revision=NULL" ":conflict_object=NULL" ":shared_object=NULL"
run owner/upsert_mail_summary ":collection='INBOX'" ":link_id='a'" ":message_id='a'" ":subject='s'" \
    ":sender=NULL" ":sender_name=NULL" ":date='2026-10-06T08:00:00Z'" ":size=1" ":attachment=0"
run owner/open_round ":collection='INBOX'" ":source='imap'" ":since='2026-09-01T00:00:00Z'" ":until='2026-10-01T00:00:00Z'" ":band=0"
run owner/close_round ":collection='INBOX'" ":source='imap'" ":checkpoint=NULL" ":since='2026-09-01T00:00:00Z'" ":until='2026-10-01T00:00:00Z'"
run owner/open_round ":collection='INBOX'" ":source='imap'" ":since='2026-09-01T00:00:00Z'" ":until='2026-10-01T00:00:00Z'" ":band=0"
run queue/enqueue_action ":producer='p'" ":collection='INBOX'" ":action='remove'" ":payload='{\"v\":1,\"seq\":1}'" > /dev/null
run owner/record_receipt ":id=9" ":collection='INBOX'" ":seq=1"
run owner/set_capability ":account=NULL" ":source='imap'" ":collection=NULL" ":capability='mail.submit'" ":support='full'" ":detail=NULL"
run owner/set_performer ":account=NULL" ":capability='mail.submit'" ":source='imap'"
sql "INSERT INTO items(collection, link_id, seq, level, deleted, retained_at, retained_by) VALUES('INBOX', 'r', 2, 2, 1, '2026-10-01T00:00:00.000Z', 'imap');
     INSERT INTO event_summary(item, summary, recurring) SELECT id, '', 0 FROM items WHERE link_id = 'a';
     INSERT INTO task_summary(item, summary, recurring) SELECT id, '', 0 FROM items WHERE link_id = 'a';
     INSERT INTO file_summary(item, name, size) SELECT id, '', 0 FROM items WHERE link_id = 'a';
     INSERT INTO item_reference(from_kind, from_link_id, to_kind, to_link_id, role, origin, created_at)
         VALUES('message/rfc822', 'a', 'message/rfc822', 'r', 'related', 'user', '2026-10-01T00:00:00.000Z');"
shapes="$(sqlite3 "$dir/pimdir.db" .dump)"
refusals=0
while IFS='|' read -r column write; do
    [ -n "$column" ] || continue
    refusals=$((refusals + 1))
    expect "shape: [$write] is refused by the CHECK on $column" \
        "$(sql "$write;" 2>&1 | grep -c "CHECK constraint failed: $column" || true)" "1"
done <<'SHAPES'
retained_at GLOB|UPDATE items SET retained_at = 'yesterday' WHERE link_id = 'r'
retained_at GLOB|UPDATE items SET retained_at = '2026-10-01T00:00:00Z' WHERE link_id = 'r'
retained_at GLOB|UPDATE items SET retained_at = '2026-10-01T00:00:00.000+00:00' WHERE link_id = 'r'
retained_at GLOB|UPDATE items SET retained_at = '2026-10-01 00:00:00.000Z' WHERE link_id = 'r'
created_at GLOB|UPDATE store_meta SET created_at = '2026-10-01T00:00:00Z'
created_at GLOB|UPDATE queue SET created_at = '1790000000'
created_at GLOB|UPDATE item_reference SET created_at = '2026-10-01'
applied_at GLOB|UPDATE receipts SET applied_at = '2026-10-01T00:00:00Z'
covered_at GLOB|UPDATE sources SET covered_at = '2026-10-01T00:00:00Z'
round_started_at GLOB|UPDATE sources SET round_started_at = '2026-10-01T00:00:00Z'
covered_since GLOB|UPDATE sources SET covered_since = '2026-09-01'
covered_until GLOB|UPDATE sources SET covered_until = '2026-10-01T00:00:00.000Z'
round_since GLOB|UPDATE sources SET round_since = '2026-09-01T00:00:00'
round_until GLOB|UPDATE sources SET round_until = ''
seq >= 1|UPDATE items SET seq = 0 WHERE link_id = 'a'
seq >= 1|INSERT INTO items(collection, link_id, seq, level) VALUES('INBOX', 'n', -3, 2)
seq >= 1|UPDATE receipts SET seq = 0
link_id != ''|INSERT INTO items(collection, link_id, seq, level) VALUES('INBOX', '', 3, 2)
id != ''|INSERT INTO collections(id, kind, name) VALUES('', 'message/rfc822', '')
account != ''|UPDATE collections SET account = ''
account != ''|UPDATE capabilities SET account = ''
account != ''|UPDATE performers SET account = ''
source != ''|UPDATE sources SET source = ''
source != ''|UPDATE bindings SET source = ''
source != ''|UPDATE capabilities SET source = ''
source != ''|UPDATE performers SET source = ''
handle != ''|UPDATE bindings SET handle = ''
size >= 0|UPDATE objects SET size = -5
date GLOB|UPDATE mail_summary SET date = '12 Nov 2026'
date GLOB|UPDATE mail_summary SET date = '2026-10-06T08:00:00.000Z'
date GLOB|UPDATE mail_summary SET date = '2026-10-06T08:00:00+00:00'
size >= 0|UPDATE mail_summary SET size = -1
size >= 0|UPDATE file_summary SET size = -1
attempts >= 0|UPDATE queue SET attempts = -1
attachment IN (0, 1)|UPDATE mail_summary SET attachment = 7
recurring IN (0, 1)|UPDATE event_summary SET recurring = 2
recurring IN (0, 1)|UPDATE task_summary SET recurring = -1
retained_by IS NULL OR retained_at IS NOT NULL|UPDATE items SET retained_by = 'imap' WHERE link_id = 'a'
retained_by IS NULL OR retained_at IS NOT NULL|UPDATE items SET retained_at = NULL WHERE link_id = 'r'
SHAPES
expect "shape: 39 writes refused, no row moved, and what each column may also hold is taken" \
    "$refusals|$([ "$(sqlite3 "$dir/pimdir.db" .dump)" = "$shapes" ] && echo unmoved)|$(sql "UPDATE mail_summary SET date = NULL, size = NULL, attachment = NULL; UPDATE event_summary SET recurring = NULL; UPDATE task_summary SET recurring = 1;
        UPDATE sources SET covered_since = NULL, round_until = NULL; UPDATE receipts SET seq = NULL; UPDATE items SET retained_by = NULL WHERE link_id = 'r';
        UPDATE objects SET size = 0; SELECT 'taken';")" \
    "39|unmoved|taken"

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
sql "UPDATE items SET object = (SELECT id FROM objects WHERE hash = '$hc'), level = 2 WHERE collection = 'INBOX' AND link_id = 'c';"
expect "sum: held 1 is what a release frees, held 0 what a download fetches" \
    "$(run read/sum_mail "$both" ":seen=NULL" ":attachment=NULL" ":held=1" ":since=NULL" ":until=NULL")|$(run read/sum_mail "$both" ":seen=NULL" ":attachment=NULL" ":held=0" ":since=NULL" ":until=NULL")" \
    "1|50|0|3|100|2"
sql "UPDATE items SET object = (SELECT id FROM objects WHERE hash = '$hc'), level = 2 WHERE collection = 'Sent' AND link_id = 'a';"
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
    local cursor=(":after_key=NULL" ":after_seq=NULL" ":after_collection=NULL")
    shift 2
    IFS=, read -r k s c r <<<"$fields"
    [ -z "$r" ] || cursor[3]=":after_role=NULL"
    while :; do
        rows="$(run "read/$statement" "$@" "${cursor[@]}" ":limit=2" || true)"
        [ -n "$rows" ] || break
        out="$out$(cut -d'|' -f1,2 <<<"$rows" | tr '\n' ' ')"
        [ "$(grep -c . <<<"$rows")" -eq 2 ] || break
        last="$(tail -1 <<<"$rows")"
        cursor=(":after_key='$(cut -d'|' -f"$k" <<<"$last")'" ":after_seq=$(cut -d'|' -f"$s" <<<"$last")"
                ":after_collection='$(cut -d'|' -f"$c" <<<"$last")'")
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
    index=items_by_sort
    [ "$statement" != count_unread ] || index=items_unread
    expect "since: $statement seeks the floor on $index" \
        "$(plan "read/$statement" "$both" ":since='2026-10-06T00:00:00Z'" | grep -c "$index (collection=? AND sort_key>?)" || true)" "1"
    expect "count: $statement joins no summary, reading it for the attachment chip alone" \
        "$(plan "read/$statement" "$both" ":seen=NULL" ":attachment=NULL" ":since=NULL" ":shift=NULL" | grep -c 'mail_summary.*LEFT-JOIN' || true)" "0"
done
# The unread count reads the partial index holding the unread rows alone
# (§14.1), with no floor too, and never the order every live row is in: a
# mailbox mostly read counts what it has not read.
expect "count: count_unread seeks items_unread, never items_by_sort nor the whole table" \
    "$(plan read/count_unread "$both" ":attachment=NULL" ":since=NULL" | grep -c 'SEARCH i USING INDEX items_unread (collection=? AND sort_key>?)' || true)$(plan read/count_unread "$both" ":attachment=NULL" ":since=NULL" | grep -cE 'items_by_sort|SCAN i\b' || true)" "10"
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
sql "UPDATE bindings SET base_object = (SELECT id FROM objects WHERE hash = '$h1') WHERE item IN (SELECT id FROM items WHERE link_id = 'k');"
minted="dup:k#$(printf '\001')k"
sql "INSERT INTO items(collection, link_id, seq, flags_known, level) VALUES('INBOX', '$minted', 2, 1, 2);
     INSERT INTO bindings(item, collection, source, handle) VALUES((SELECT id FROM items WHERE collection = 'INBOX' AND link_id = '$minted'), 'INBOX', 'imap', char(1) || '$minted');"
expect "origin: a create keyed by the key minted over its provisional handle pairs with the key's holder, of the body it intends" \
    "$(run owner/origin_for_link ":link_id='$minted'" ":source='imap'" ":collection='INBOX'" ":hash=NULL")|$(run owner/origin_for_link ":link_id='$minted'" ":source='imap'" ":collection='INBOX'" ":hash='$h1'")|$(run owner/origin_for_link ":link_id='$minted'" ":source='imap'" ":collection='INBOX'" ":hash='$h2'")|$(run owner/origin_for_link ":link_id='$minted'" ":source='graph'" ":collection='INBOX'" ":hash=NULL")" \
    "Archive|10|Archive|10||"
expect "destination: a tombstone pairs with the pending create of its key minted elsewhere" \
    "$(run owner/destination_for_link ":link_id='k'" ":source='imap'" ":collection='Archive'" | cut -d'|' -f1)|$(run owner/destination_for_link ":link_id='k'" ":source='imap'" ":collection='INBOX'")" \
    "INBOX|"
for statement in origin_for_link destination_for_link; do
    expect "placement: $statement seeks items_by_link, then the binding's key, never every binding" \
        "$(plan "owner/$statement" ":link_id='$minted'" ":source='imap'" ":collection='INBOX'" ":hash=NULL" | grep -cE 'items_by_link \(link_id=\?\)|bindings_1 \(item=\? AND source=\?\)' || true)" "2"
done

# --- A delivered create is no member a listing names (SYNC.md §2, §4, §5) ---

fresh
collection INBOX
collection Trash
p="$(printf '\001')"
mail INBOX kept 1 10 "'2026-10-06T08:00:00Z'"
seq=1
for key in moved landed; do
    seq=$((seq + 1))
    run owner/insert_item ":collection='Trash'" ":link_id='$key'" ":seq=$seq" ":flags='[]'" \
        ":object_hash=NULL" ":sort_key=''" ":level=1" ":deleted=0" ":conflicted=0" ":conflict_object=NULL"
    run owner/upsert_mail_summary ":collection='Trash'" ":link_id='$key'" ":message_id='$key'" \
        ":subject='s $key'" ":sender='alice@example.org'" ":sender_name='Alice'" \
        ":date='2026-10-06T08:00:00Z'" ":size=1" ":attachment=0"
done
run owner/insert_binding ":collection='Trash'" ":link_id='moved'" ":source='imap'" ":handle='${p}moved'" \
    ":base_flags=NULL" ":base_object=NULL" ":base_revision=NULL" ":base_present=0" \
    ":conflicted=0" ":conflict_revision=NULL" ":conflict_object=NULL" ":shared_object=NULL"
run owner/insert_binding ":collection='Trash'" ":link_id='landed'" ":source='imap'" ":handle='7'" \
    ":base_flags=NULL" ":base_object=NULL" ":base_revision=NULL" ":base_present=0" \
    ":conflicted=0" ":conflict_revision=NULL" ":conflict_object=NULL" ":shared_object=NULL"
base() {
    sql "SELECT group_concat(state, ' ') FROM (SELECT i.link_id || ':' || b.base_present || b.base_flags_known || b.base_marks
         || coalesce((SELECT hash FROM objects WHERE id = b.base_object), '-') || coalesce(b.base_revision, '-') AS state
         FROM bindings b JOIN items i ON i.id = b.item WHERE b.collection = 'Trash' ORDER BY i.link_id);"
}
run owner/deliver_binding ":collection='Trash'" ":source='imap'" ":handle='${p}moved'"
run owner/deliver_binding ":collection='Trash'" ":source='imap'" ":handle='7'"
run owner/deliver_binding ":collection='Trash'" ":source='imap'" ":handle='${p}gone'"
expect "delivered: a pending create gains a base naming nothing, a member's handle and an unbound one stay as they are" \
    "$(base)" "landed:000-- moved:100--"
run owner/deliver_binding ":collection='Trash'" ":source='graph'" ":handle='${p}moved'"
expect "delivered: delivering twice, or for another source, moves nothing" "$(base)" "landed:000-- moved:100--"
expect "delivered: a delivered create is no origin a copy comes from" \
    "$(run owner/origin_for_link ":link_id='moved'" ":source='imap'" ":collection='INBOX'" ":hash=NULL")|$(run owner/origin_for_link ":link_id='kept'" ":source='imap'" ":collection='Trash'" ":hash=NULL")" \
    "|INBOX|10"
expect "delivered: a delivered create stays the destination a tombstone of its identity relocates into" \
    "$(run owner/destination_for_link ":link_id='moved'" ":source='imap'" ":collection='INBOX'" | cut -d'|' -f1)" "Trash"
run owner/open_round ":collection='Trash'" ":source='imap'" ":since=NULL" ":until=NULL" ":band=0"
run owner/update_binding ":collection='Trash'" ":link_id='landed'" ":source='imap'" ":base_flags_known=0" ":base_marks=0" \
    ":base_object=NULL" ":base_revision=NULL" ":base_present=1" ":conflicted=0" ":conflict_revision=NULL" \
    ":conflict_object=NULL" ":shared_object=NULL"
expect "delivered: a round's last page finds a based member absent, never a delivered create" \
    "$(run owner/list_unstamped_bindings ":collection='Trash'" ":source='imap'" ":narrowed=0" ":enumerated=0" | tr '\n' ' ')" "7|landed "

# --- A refused push stands on its binding and shows on its receipt (§4.3, §13,
# §15.4, SYNC.md §5) -----------------------------------------------------------
# A remote refusing a change for good leaves its reason and key on the binding
# it was pushed for; an upsert keeps it, the next accepted push clears it, and
# it goes with its binding. A receipt names the item its row acted on, reads
# the refusals of that item in its own account, and is kept while one stands.

fresh
collection INBOX
collection Drafts
collection Other "'work'"
p="$(printf '\001')"
item INBOX mid:a 7
bind INBOX mid:a graph "${p}mid:a" 0
bind INBOX mid:a imap 10 1
item INBOX mid:b 8
bind INBOX mid:b graph 20 1
item Other mid:a 7
bind Other mid:a graph 30 1
# refusals <collection>: its refusals, the handle left out, which the CLI
# prints escaped when provisional.
refusals() {
    run read/list_refusals ":collection='$1'" | cut -d'|' -f1,2,4,5 | tr '\n' ' '
}
run owner/refuse_binding ":collection='INBOX'" ":source='graph'" ":handle='${p}mid:a'" \
    ":key='0123456789abcdef'" ":reason='append to Drafts only'"
run owner/refuse_binding ":collection='INBOX'" ":source='graph'" ":handle='${p}gone'" \
    ":key='0123456789abcdef'" ":reason='nothing binds it'"
run owner/refuse_binding ":collection='Other'" ":source='graph'" ":handle='30'" \
    ":key='fedcba9876543210'" ":reason='another account'"
expect "refused: a refusal stands on the binding pushed for, none where nothing binds the handle" \
    "$(refusals INBOX)" "7|graph|append to Drafts only|0123456789abcdef "
expect "refused: SQLite stamps when, in the shape of §13" \
    "$(sql "SELECT count(*) FROM bindings WHERE refused_at GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9].[0-9][0-9][0-9]Z';")" "2"
fails owner/refuse_binding ":collection='INBOX'" ":source='graph'" ":handle='20'" ":key=NULL" ":reason='no key'" &&
    fails owner/refuse_binding ":collection='INBOX'" ":source='graph'" ":handle='20'" ":key='0123456789ABCDEF'" ":reason='a key of another shape'"
expect "refused: a refusal states its key, sixteen lowercase hexadecimal digits" "$?" "0"
run owner/update_binding ":collection='INBOX'" ":link_id='mid:a'" ":source='graph'" ":base_flags_known=0" ":base_marks=0" \
    ":base_object=NULL" ":base_revision=NULL" ":base_present=0" ":conflicted=0" ":conflict_revision=NULL" \
    ":conflict_object=NULL" ":shared_object=NULL"
expect "refused: an upsert of the binding keeps the refusal" \
    "$(refusals INBOX)" "7|graph|append to Drafts only|0123456789abcdef "
run owner/record_receipt ":id=1" ":collection='INBOX'" ":seq=7"
run owner/record_receipt ":id=2" ":collection='INBOX'" ":seq=8"
run owner/record_receipt ":id=3" ":collection='Drafts'" ":seq=7"
expect "refused: a receipt keeps its columns and reads the refusal on its item, in its own account" \
    "$(run read/load_receipt ":id=1" | cut -d'|' -f2,3)|$(run read/load_receipt_refusals ":id=1" | cut -d'|' -f1-3 | tr '\n' ' ')" \
    "INBOX|7|INBOX|graph|append to Drafts only "
expect "refused: a move's receipt reads the create it left in its target" \
    "$(run read/load_receipt_refusals ":id=3" | cut -d'|' -f1-3)" "INBOX|graph|append to Drafts only"
expect "refused: a receipt whose item no refusal stands on reads none" \
    "$(run read/load_receipt_refusals ":id=2")" ""
run owner/prune_receipts ":before='9999-01-01T00:00:00.000Z'"
expect "refused: pruning keeps a receipt while a refusal stands on its item" \
    "$(sql "SELECT group_concat(id, ' ') FROM (SELECT id FROM receipts ORDER BY id);")" "1 3"
run owner/clear_refusal ":collection='INBOX'" ":source='graph'" ":handle='${p}mid:a'"
expect "refused: an accepted push clears the refusal, another account's standing" \
    "$(refusals INBOX)|$(run read/load_receipt_refusals ":id=1")|$(refusals Other)" \
    "||7|graph|another account|fedcba9876543210 "
run owner/prune_receipts ":before='9999-01-01T00:00:00.000Z'"
expect "refused: cleared, the receipt is pruned as any other" "$(sql "SELECT count(*) FROM receipts;")" "0"
run owner/refuse_binding ":collection='INBOX'" ":source='graph'" ":handle='${p}mid:a'" \
    ":key='0123456789abcdef'" ":reason='append to Drafts only'"
run owner/delete_binding ":collection='INBOX'" ":link_id='mid:a'" ":source='graph'"
expect "refused: a withdrawal takes the refusal with its binding" "$(refusals INBOX)" ""

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
     INSERT INTO mail_in_reply_to(item, position, message_id) VALUES((SELECT id FROM items WHERE collection = 'INBOX' AND link_id = 'a'), 0, 'p'), ((SELECT id FROM items WHERE collection = 'INBOX' AND link_id = 'b'), 0, 'q');
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
    "$(run owner/purge_retained_before ":before='2026-10-01T00:00:00.000Z'" | tr '\n' ' ')|$(sql "SELECT group_concat(link_id, ' ') FROM (SELECT link_id FROM items ORDER BY link_id);")" \
    "$h1| $h1| |live new"
for statement in owner/purge_retained_before read/retained_bytes; do
    expect "purge: ${statement#*/} reads items_by_retained, never every item" \
        "$(plan "$statement" ":before='2026-06-01T00:00:00.000Z'" | grep -c 'items_by_retained' || true)$(plan "$statement" ":before='2026-06-01T00:00:00.000Z'" | grep -c 'SCAN items' || true)" "10"
done

# --- Small rows carry no rowid, a pointer index the pointers set (§4.3) -----

fresh
expect "schema: the tables of a few short columns carry no rowid" \
    "$(sql "SELECT group_concat(name, ' ') FROM (SELECT name FROM pragma_table_list WHERE schema = 'main' AND wr = 1 ORDER BY name);")" \
    "binding_base_flag item_address item_property item_reference mail_in_reply_to placement_flag supersessions task_category"

expect "schema: a pointer index holds the set pointers alone, items_by_object too, and items_bodiless the rest, live, which coverage reads" \
    "$(sql "SELECT group_concat(name, ' ') FROM (SELECT name FROM sqlite_schema WHERE type = 'index' AND name GLOB '*_object'
            AND sql GLOB '* IS NOT NULL' ORDER BY name);")|$(sql "SELECT sql FROM sqlite_schema WHERE name = 'items_bodiless';")" \
    "bindings_by_conflict_object bindings_by_object bindings_by_shared_object items_by_conflict_object items_by_object queue_by_object|CREATE INDEX items_bodiless ON items(collection, deleted, object) WHERE object IS NULL AND deleted = 0"
# opens <statement>: the tables and indexes its program reads, foreign keys
# on, by name.
opens() {
    sqlite3 -separator ' ' "$dir/pimdir.db" "PRAGMA foreign_keys = ON; EXPLAIN $1" | awk '$2 == "OpenRead" {print $4}' | sort -u |
        while read -r root; do sql "SELECT name FROM sqlite_schema WHERE rootpage = $root;"; done | sort | tr '\n' ' '
}
expect "schema: an object's delete checks every pointer at it on its index, never reading items, bindings or the queue" \
    "$(opens "DELETE FROM objects WHERE id = 1;")" \
    "bindings_by_conflict_object bindings_by_object bindings_by_shared_object items_by_conflict_object items_by_object queue_by_object "

# --- An object is keyed by an integer, named by its hash (§4.3, §4.4) -------

# Every pointer at a body is the object's id: each foreign key onto objects
# names `id`, and a pointer holding a name is refused, so no index on a
# pointer is keyed by a random 52-character text.
fresh
collection INBOX
item INBOX a 1
run queue/enqueue_action ":producer='p'" ":collection='INBOX'" ":action='remove'" ":payload='{\"v\":1,\"seq\":1}'" \
    ":target_collection=NULL" ":object_hash=NULL" > /dev/null
run owner/insert_binding ":collection='INBOX'" ":link_id='a'" ":source='imap'" ":handle='1'" ":base_flags=NULL" \
    ":base_object=NULL" ":base_revision=NULL" ":base_present=1" ":conflicted=1" ":conflict_revision=NULL" \
    ":conflict_object=NULL" ":shared_object=NULL"
expect "objects: every pointer at a body is a foreign key onto objects.id, and a pointer holding a name is refused" \
    "$(sql "SELECT group_concat(name || '.' || \"from\" || '>' || \"to\", ' ') FROM (SELECT t.name, f.\"from\", f.\"to\"
            FROM sqlite_schema t, pragma_foreign_key_list(t.name) f WHERE t.type = 'table' AND f.\"table\" = 'objects'
            ORDER BY t.name, f.\"from\");")|$(for write in "items SET object" "items SET conflicted = 1, conflict_object" \
            "bindings SET base_object" "bindings SET conflict_object" "bindings SET shared_object" "queue SET object"; do
               sql "UPDATE $write = '$h1';" 2>&1 | grep -c 'CHECK constraint failed: typeof' || true
           done | tr -d '\n')" \
    "bindings.base_object>id bindings.conflict_object>id bindings.shared_object>id items.conflict_object>id items.object>id queue.object>id|111111"

# The id is drawn at insert above every id drawn before, so a body stored
# after the collector took the last one never reuses its id, and an index on
# a pointer grows at its end.
fresh
object "$h1"
object "$h2"
run owner/recompute_refcounts
run owner/delete_garbage_objects
object "$h3"
object "$h1"
object "$h3"
expect "objects: an id is drawn above every id drawn before, the collected ones' included, and a body stored again keeps its own" \
    "$(sql "SELECT (SELECT id FROM objects WHERE hash = '$h3') || ' ' || (SELECT id FROM objects WHERE hash = '$h1');")|$(sql "SELECT count(*) FROM objects;")" "3 4|2"

# A statement takes a body by its hash and writes its id: a hash naming no
# object row fails, whichever statement names it, and every read answers the
# hash.
fresh
collection INBOX
object "$h1"
object "$h2"
item INBOX a 1 "'$h1'"
mail_row() {
    run owner/insert_item ":collection='INBOX'" ":link_id='$1'" ":seq=$2" ":flags='[]'" ":object_hash=$3" ":sort_key=''" \
        ":level=2" ":deleted=0" ":conflicted=$4" ":conflict_object=$5"
}
expect "objects: a write naming a body no object row holds is refused, by its hash or its conflict's" \
    "$(mail_row b 2 "'$h3'" 0 NULL 2>&1 | grep -c 'FOREIGN KEY constraint failed')$(mail_row b 2 "'$h1'" 1 "'$h3'" 2>&1 | grep -c 'FOREIGN KEY constraint failed')$(run owner/update_item ":collection='INBOX'" ":link_id='a'" ":flags='[]'" ":object_hash='$h3'" ":sort_key=''" \
        ":level=2" ":deleted=0" ":conflicted=0" ":conflict_object=NULL" 2>&1 | grep -c 'FOREIGN KEY constraint failed')$(run owner/insert_binding ":collection='INBOX'" ":link_id='a'" ":source='imap'" ":handle='1'" ":base_flags=NULL" \
        ":base_object='$h1'" ":base_revision=NULL" ":base_present=1" ":conflicted=0" ":conflict_revision=NULL" \
        ":conflict_object=NULL" ":shared_object='$h3'" 2>&1 | grep -c 'FOREIGN KEY constraint failed')|$(sql "SELECT count(*) FROM items;")" \
    "1111|1"
mail_row b 2 "'$h2'" 1 "'$h1'"
run owner/insert_binding ":collection='INBOX'" ":link_id='b'" ":source='imap'" ":handle='2'" ":base_flags=NULL" \
    ":base_object='$h1'" ":base_revision=NULL" ":base_present=1" ":conflicted=0" ":conflict_revision=NULL" \
    ":conflict_object=NULL" ":shared_object='$h2'"
expect "objects: a body named by its hash is written as its id and read back as its hash" \
    "$(sql "SELECT i.object = o.id FROM items i, objects o WHERE i.link_id = 'b' AND o.hash = '$h2';")|$(run owner/load_items ":collection='INBOX'" | grep '^b|' | cut -d'|' -f3,8)|$(run owner/load_bindings ":collection='INBOX'" | cut -d'|' -f5,11)|$(run read/get_item ":collection='INBOX'" ":seq=2" | cut -d'|' -f4)" \
    "1|$h2|$h1|$h1|$h2|$h2"
# A hot statement naming a body by its hash seeks each name on
# objects_by_hash, then the pointer by the id; a read answering the hash
# reads it by the id, the row's key; and the collector's recount joins ids
# alone, reading no name.
expect "objects: a write and a lookup by hash seek objects_by_hash, then the pointer index by id" \
    "$(plan owner/insert_item ":object_hash='$h1'" ":conflict_object=NULL" | grep -c 'SEARCH objects USING COVERING INDEX objects_by_hash (hash=?)' || true)$(plan read/list_object_placements ":hash='$h1'" | grep -cE 'SEARCH objects USING COVERING INDEX objects_by_hash \(hash=\?\)|SEARCH i USING INDEX items_by_object \(object=\?\)' || true)$(plan owner/held_elsewhere ":collection='INBOX'" ":link_id='a'" ":hash='$h1'" | grep -c 'SEARCH objects USING COVERING INDEX objects_by_hash (hash=?)' || true)" \
    "221"
expect "objects: a read answers a body's hash by its id, and the recount joins ids alone" \
    "$(plan read/list_mail_page_desc ":collection='INBOX'" ":after_key=NULL" ":after_seq=NULL" ":limit=10" | grep -c 'SEARCH o USING INTEGER PRIMARY KEY (rowid=?)' || true)$(plan owner/recompute_refcounts | grep -c 'objects_by_hash' || true)$(plan owner/recompute_refcounts | grep -cE 'SEARCH (items|bindings|queue) USING COVERING INDEX (items_by_object|items_by_conflict_object|bindings_by_object|bindings_by_conflict_object|bindings_by_shared_object|queue_by_object) ' || true)" \
    "106"

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
# A reserved prefix is compared byte for byte (§9): a stated identity
# spelling one in another case is a stated key like any other, and is linked.
item Work 'Hash:x' 6 "'$h4'"
item Work 'ALT:y' 7 "'$h5'"
links=":links='[\"k@x\",\"alt:s|d|f\",\"hash:0123456789abcdef\",\"dup:k@x#7\",\"meta@x\",\"Hash:x\",\"ALT:y\"]'"
expect "lookup: an account's body for a stated key, with its size, one spelling a reserved prefix in another case included, never another account's, a derived or a minted key's, nor a bodiless row's" \
    "$(run owner/lookup_objects ":account='work'" "$links" | LC_ALL=C sort -u | tr '\n' ' ')|$(run owner/lookup_objects ":account='home'" "$links" | tr '\n' ' ')|$(run owner/lookup_objects ":account=NULL" "$links" | tr '\n' ' ')" \
    "ALT:y|$h5|1||| Hash:x|$h4|1||| k@x|$h1|1||| |k@x|$h2|1||| |k@x|$h3|1||| "
# The agreement of §9 guards a link across collections (SYNC.md §6): each
# holder answers the subject, date and sender its summary states beside its
# body, one row per holder, so a caller adopts a body only from a row agreeing
# with its member, and fetches when a message reusing the Message-ID in
# another collection is all the account holds. A row with no summary states
# the three as NULL, which no message agrees with: its subject is never NULL.
run owner/upsert_mail_summary ":collection='Work'" ":link_id='k@x'" ":message_id='k@x'" ":subject='Notice'" \
    ":sender='cron@x'" ":sender_name=NULL" ":date='2026-08-01T10:00:00Z'" ":size=1" ":attachment=NULL" ":invitation=NULL"
sql "UPDATE items SET object = (SELECT id FROM objects WHERE hash = '$h2') WHERE collection = 'Work2' AND link_id = 'k@x';"
run owner/upsert_mail_summary ":collection='Work2'" ":link_id='k@x'" ":message_id='k@x'" ":subject='Notice'" \
    ":sender=NULL" ":sender_name=NULL" ":date=NULL" ":size=1" ":attachment=NULL" ":invitation=NULL"
expect "lookup: each holder of a key answers its body with the subject, date and sender its row states, two messages under one Message-ID as two rows" \
    "$(run owner/lookup_objects ":account='work'" ":links='[\"k@x\"]'" | LC_ALL=C sort | tr '\n' ' ')" \
    "k@x|$h2|1|Notice|| k@x|$h1|1|Notice|2026-08-01T10:00:00Z|cron@x "
sql "UPDATE items SET object = (SELECT id FROM objects WHERE hash = '$h1') WHERE collection = 'Work2' AND link_id = 'k@x';
     DELETE FROM mail_summary WHERE item IN (SELECT id FROM items WHERE link_id = 'k@x');"
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
summary Work 'Hash:x' 1 "'cased@x'"
sql "UPDATE items SET object = (SELECT id FROM objects WHERE hash = '$h1') WHERE link_id = 'alt:s|d|f';"
expect "held: a body's columns come from a row of the account holding it, one stating its mark first, never another account's nor a derived key's" \
    "$(run owner/held_mail_summary ":account='work'" ":link_id='k@x'" ":hash='$h1'")|$(run owner/held_mail_summary ":account='home'" ":link_id='k@x'" ":hash='$h1'")|$(run owner/held_mail_summary ":account='home'" ":link_id='k@x'" ":hash='$h2'")|$(run owner/held_mail_summary ":account='work'" ":link_id='alt:s|d|f'" ":hash='$h1'")" \
    "1|ev@x||0||"
expect "held: a stated key spelling a reserved prefix in another case is held like any other" \
    "$(run owner/held_mail_summary ":account='work'" ":link_id='Hash:x'" ":hash='$h4'")" "1|cased@x"

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
    "$(sql "SELECT i.seq, o.hash, i.deleted, i.retained_at IS NULL, i.retained_by IS NULL FROM items i LEFT JOIN objects o ON o.id = i.object WHERE i.collection = 'INBOX' AND i.link_id = 'a';")|$(run read/count_retained ":collection='INBOX'")|$(run owner/retained_item ":collection='INBOX'" ":link_id='a'")|$(sql "SELECT deleted FROM items WHERE collection = 'Archive';")" \
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
# NULL is the first page in every paged read (§9.3, §14.1), the values that
# were the first page before still accepted, and the cursor coalesced rather
# than tested, so the page stays a seek on its index at any depth.
for statement in list_items_page_asc list_contacts_page_asc list_events_page_asc list_tasks_page_asc list_journals_page_asc list_files_page_asc; do
    expect "page: $statement reads a NULL cursor as the first page, as the empty key with seq 0" \
        "$(pages "$statement" NULL NULL ":collection='C'")|$(run "read/$statement" ":collection='C'" ":after_key=NULL" ":after_seq=NULL" ":limit=9" | cut -d'|' -f1 | tr '\n' ' ')" \
        "2 3 4 1 5 |2 3 4 1 5 "
    expect "page: $statement seeks a NULL cursor on items_by_sort, sorting nothing" \
        "$(plan "read/$statement" ":collection='C'" ":after_key=NULL" ":after_seq=NULL" ":limit=2" | grep -c 'items_by_sort (collection=? AND (sort_key,seq)>(?,?))' || true)$(plan "read/$statement" ":collection='C'" ":after_key=NULL" ":after_seq=NULL" ":limit=2" | grep -c 'TEMP B-TREE' || true)" "10"
done
expect "page: list_items_page and list_retained_page read a NULL cursor as the first page, as '' and 0" \
    "$(run read/list_items_page ":collection='C'" ":after=NULL" ":limit=3" | cut -d'|' -f2 | tr '\n' ' ')|$(run read/list_retained_page ":collection='C'" ":after=NULL" ":limit=3" | cut -d'|' -f2)|$(run read/list_retained_page ":collection='C'" ":after=0" ":limit=3" | cut -d'|' -f2)|$(run read/list_retained_page ":collection='C'" ":after=6" ":limit=3" | cut -d'|' -f2)" \
    "a b c |f|f|"
expect "page: both seek a NULL cursor, the sweep on the item's key and the trash on items_deleted, sorting nothing" \
    "$(plan read/list_items_page ":collection='C'" ":after=NULL" ":limit=3" | grep -c 'sqlite_autoindex_items_1 (collection=? AND link_id>?)' || true)$(plan read/list_retained_page ":collection='C'" ":after=NULL" ":limit=3" | grep -c 'items_deleted (collection=? AND seq>?)' || true)$({ plan read/list_items_page ":collection='C'" ":after=NULL" ":limit=3"; plan read/list_retained_page ":collection='C'" ":after=NULL" ":limit=3"; } | grep -c 'TEMP B-TREE' || true)" "110"

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
for kind in event task journal; do
    run "owner/delete_${kind}_summary" ":collection='Cal'" ":link_id='${kind:0:1}'"
done
expect "delete: a calendar summary goes alone, the item still read, through no table" \
    "$(sql "SELECT count(*) FROM event_summary; SELECT count(*) FROM task_summary; SELECT count(*) FROM journal_summary; SELECT count(*) FROM items WHERE collection = 'Cal';" | tr '\n' ' ')|$(run read/get_event ":collection='Cal'" ":seq=1" | cut -d'|' -f2,8)" \
    "0 0 0 3 |e|"

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
    run owner/insert_in_reply_to ":collection='INBOX'" ":link_id='$link'" ":position=$position" ":message_id='$id'"
done
run owner/replace_in_reply_to ":collection='INBOX'" ":link_id='m'"
run owner/insert_in_reply_to ":collection='INBOX'" ":link_id='m'" ":position=0" ":message_id='s@x'"
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

# --- An intent whose outcome is unknown is parked apart (§15.2, §15.5) ------
# A submission cut once the message was handed over is parked under the one
# reserved prefix of queue.error. No drain lists a parked row, so nothing
# retries it; a producer tells it from any other parked row by the prefix. It
# leaves that state confirmed (acknowledged with its receipt), retried on
# request (retry_action) or withdrawn.

fresh
collection Sent
object "$m1"
for subject in first second; do
    run queue/pin_object ":hash='$m1'"
    run queue/enqueue_action ":producer='p'" ":collection='Sent'" ":action='submit'" ":payload='{\"v\":1,\"source\":\"smtp\",\"from\":\"alice@example.org\",\"rcpts\":[\"bob@example.org\"],\"subject\":\"$subject\"}'" ":target_collection=NULL" ":object_hash='$m1'"
done
run queue/enqueue_action ":producer='p'" ":collection='Sent'" ":action='remove'" ":payload='{\"v\":1,\"seq\":9}'" ":target_collection=NULL" ":object_hash=NULL"
expect "unconfirmed: unconfirm_action answers the intent it parked, the attempt counted, and nothing for a row that is gone" \
    "$(run owner/unconfirm_action ":id=1" ":detail='the connection dropped after the message was handed over'")|$(run owner/unconfirm_action ":id=2" ":detail='no answer to the final dot'")|$(run owner/unconfirm_action ":id=7" ":detail='gone'")|$(sql "SELECT group_concat(attempts, ' ') FROM queue WHERE id IN (1, 2);")" "1|2||1 1"
expect "unconfirmed: an action the owner applies itself is never one, its row left pending and uncounted" \
    "$(run owner/unconfirm_action ":id=3" ":detail='a remove commits or does not'")|$(sql "SELECT attempts || ':' || (error IS NULL) FROM queue WHERE id = 3;")" "|0:1"
run owner/park_action ":id=3" ":error='unknown seq: 9'"
expect "unconfirmed: no drain lists it, so nothing performs it again unasked" "$(run owner/list_pending_actions | wc -l)" "0"
expect "unconfirmed: a producer reading its row tells it by the reserved prefix, from any other parked row" \
    "$(for id in 1 2 3; do run read/load_action ":id=$id" | cut -d'|' -f9 | grep -c '^unconfirmed: ' || true; done | tr '\n' ' ')" "1 1 0 "
expect "retry: retry_action answers the row it put back, pending again, its error cleared, its id and attempts kept" \
    "$(run owner/retry_action ":id=1")|$(run read/load_action ":id=1" ".nullvalue=NULL" | cut -d'|' -f1,8,9)|$(run owner/list_pending_actions | cut -d'|' -f1,9 | tr '\n' ' ')" \
    "1|1|1|NULL|1|1 "
expect "retry: a pending row and a row that is gone answer nothing, and nothing moves" \
    "$(run owner/retry_action ":id=1")$(run owner/retry_action ":id=7")|$(sql "SELECT group_concat(id || ':' || attempts || ':' || (error IS NULL), ' ') FROM queue;")" "|1:1:1 2:1:0 3:1:0"
expect "retry: any parked row is put back the same way, in its place in the append order" \
    "$(run owner/retry_action ":id=3")|$(run owner/list_pending_actions | cut -d'|' -f1 | tr '\n' ' ')" "3|1 3 "
# Confirmed: the performer learns the message went, and acknowledges the row
# with its receipt, as any performed intent (§15.5).
pin="$(run owner/cancel_action ":id=2")"
run owner/record_receipt ":id=2" ":collection='Sent'" ":seq=NULL"
run owner/release_pins ":hashes='[\"$pin\"]'"
expect "unconfirmed: confirmed by its performer, it reads as performed, its pin released" \
    "$(run read/load_action ":id=2")$(run read/load_receipt ":id=2" | cut -d'|' -f2)|$(sql "SELECT refcount FROM objects WHERE hash = '$m1';")" "Sent|1"
# Withdrawn: no receipt, which is how a producer tells it from a confirmation.
run owner/park_action ":id=3" ":error='unconfirmed: a server said so'"
expect "unconfirmed: a failure whose text begins with the reserved prefix is recorded behind failed: , whole, and reads parked" \
    "$(run read/load_action ":id=3" | cut -d'|' -f9)" "failed: unconfirmed: a server said so"
run owner/unconfirm_action ":id=1" ":detail='again'" > /dev/null
run owner/release_pins ":hashes='[\"$(run owner/cancel_action ":id=1")\"]'"
expect "unconfirmed: withdrawn, it leaves no receipt and no pin" \
    "$(run read/load_action ":id=1")$(run read/load_receipt ":id=1")|$(sql "SELECT refcount FROM objects WHERE hash = '$m1';")" "|0"

# --- Several actions in one transaction, enqueued or applied (§15.1, §15.2) -
# A producer's enqueue of several actions lands all of them or none. An
# owner's run applies each action under a savepoint of its own: a failed
# apply rolls back to its savepoint, which restores the claimed row and
# undoes what the apply wrote, the park is recorded outside it, and the
# actions around it stand; a run that does not commit applies none.

# session <line...>: one connection running the lines in order, stopping at
# the first error, so a transaction left open is rolled back by the close.
session() {
    { prelude; echo "PRAGMA foreign_keys = ON;"; echo ".bail on"; printf '%s\n' "$@"; } | sqlite3 "$dir/pimdir.db" 2>/dev/null || true
}
# bound <part/profile/name> [:param=literal...]: a statement and its bindings,
# as lines for a session.
bound() {
    local file="$1"; shift
    takes "$file" "$@"
    for binding in "$@"; do echo ".parameter set ${binding%%=*} ${binding#*=}"; done
    statement "$file"
}

fresh
collection INBOX
item INBOX a 1
item INBOX b 2
item INBOX c 3
object "$h1"
first="$(bound storage/queue/enqueue_action ":producer='p'" ":collection='INBOX'" ":action='remove'" ":payload='{\"v\":1,\"seq\":1}'" ":target_collection=NULL" ":object_hash=NULL")"
second="$(bound storage/queue/enqueue_action ":producer='p'" ":collection='INBOX'" ":action='remove'" ":payload='{\"v\":1,\"seq\":2}'" ":target_collection=NULL" ":object_hash=NULL")"
third="$(bound storage/queue/enqueue_action ":producer='p'" ":collection='INBOX'" ":action='remove'" ":payload='{\"v\":1,\"seq\":3}'" ":target_collection=NULL" ":object_hash=NULL")"
# The second names a body no row holds, which the schema refuses.
session "BEGIN;" "$first" "${second/:object_hash NULL/:object_hash \'$h2\'}" "$third" "COMMIT;"
expect "enqueue: several actions in one transaction, one refused (a body no row names): none is appended" \
    "$(sql "SELECT count(*) FROM queue;")" "0"
session "BEGIN;" "$first" "$second" "$third" "COMMIT;"
expect "enqueue: several actions in one transaction are appended together, their ids in the order enqueued" \
    "$(run owner/list_pending_actions | cut -d'|' -f1,6 | tr '\n' ' ')" "1|{\"v\":1,\"seq\":1} 2|{\"v\":1,\"seq\":2} 3|{\"v\":1,\"seq\":3} "
# apply <id> <link id> <outcome>: one action of a run under its savepoint,
# claim first; the apply tombstones the item, then either records its receipt
# and releases, or fails, rolls back to the savepoint and parks outside it.
apply() {
    echo "SAVEPOINT action;"
    bound storage/owner/claim_action ":id=$1"
    echo "UPDATE items SET deleted = 1 WHERE collection = 'INBOX' AND link_id = '$2';"
    if [ "$3" = applied ]; then
        bound storage/owner/record_receipt ":id=$1" ":collection='INBOX'" ":seq=NULL"
        echo "RELEASE action;"
    else
        echo "ROLLBACK TO action;"
        echo "RELEASE action;"
        bound storage/owner/park_action ":id=$1" ":error='refused'"
    fi
}
state() {
    sql "SELECT (SELECT group_concat(id || ':' || attempts || ':' || coalesce(error, '-'), ' ') FROM queue) || '|'
              || (SELECT coalesce(group_concat(id, ' '), '') FROM receipts) || '|'
              || (SELECT group_concat(link_id || deleted, ' ') FROM items);"
}
before="$(state)"
session "BEGIN;" "$(apply 1 a applied)" "$(apply 2 b failed)" "$(apply 3 c applied)" "ROLLBACK;" > /dev/null
expect "run: a run that does not commit applies none of its actions, each claimed row restored" "$(state)" "$before"
session "BEGIN;" "$(apply 1 a applied)" "$(apply 2 b failed)" "$(apply 3 c applied)" "COMMIT;" > /dev/null
expect "run: the actions around a failed one stand, each applied once with its receipt; the failed one is restored by its savepoint, what it wrote undone, and parked outside it" \
    "$(state)" "2:1:refused|1 3|a1 b0 c1"
expect "run: the next drain lists none of the three, the parked one read apart" \
    "$(run owner/list_pending_actions | wc -l)|$(run owner/load_parked_actions | cut -d'|' -f1)" "0|2"

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
expect "domain: the domain is compared, never a pattern, ASCII letters in either case" \
    "$(run read/list_domain_placements ":domain='e_ample.org'" ":role=NULL")$(run read/list_domain_placements ":domain='%.org'" ":role=NULL")$(run read/list_domain_placements ":domain='%'" ":role=NULL")|$(run read/list_domain_placements ":domain='Example.ORG'" ":role=NULL" | cut -d'|' -f1 | tr '\n' ' ')" \
    "|bob@example.org amy@example.org "
bind INBOX k@x imap 10 1
bind Home k@x imap 10 1
bind Solo k@x graph g1 1
sql "UPDATE bindings SET conflicted = 1, conflict_revision = 'r2', conflict_object = (SELECT id FROM objects WHERE hash = '$h3') WHERE collection = 'INBOX';
     UPDATE bindings SET conflicted = 1 WHERE collection = 'Home';
     UPDATE items SET conflicted = 1, conflict_object = (SELECT id FROM objects WHERE hash = '$h3') WHERE collection = 'INBOX' AND link_id = 'k@x';"
expect "conflicts: an account's conflicted bindings with base, local and remote, its conflicted items with both bodies, another account's apart" \
    "$(run read/list_conflicted_bindings ":account='work'" | tr '\n' ' ')|$(run read/list_conflicted_items ":account='work'" | tr '\n' ' ')|$(run read/list_conflicted_bindings ":account='home'" | cut -d'|' -f1)|$(run read/list_conflicted_items ":account='home'")" \
    "INBOX|k@x|imap|10|r2||$h1|$h3 |INBOX|k@x|1|$h1|$h3 |Home|"
expect "sources: every source holding a binding, once, sorted" "$(run read/list_sources | tr '\n' ' ')" "graph imap "
run owner/upsert_checkpoint ":collection='INBOX'" ":source='imap'" ":checkpoint=NULL"
run owner/upsert_checkpoint ":collection='INBOX'" ":source='jmap'" ":checkpoint=NULL"
sql "INSERT INTO bindings(item, collection, source, handle) SELECT id, collection, 'graph', 'g2' FROM items WHERE collection = 'INBOX' AND link_id = 'k@x';"
expect "sources: a collection's sources by a binding or a checkpoint, each once, sorted; a checkpoint alone names none store-wide" \
    "$(run owner/collection_sources ":collection='INBOX'" | tr '\n' ' ')|$(run owner/collection_sources ":collection='Solo'")|$(run owner/collection_sources ":collection='Archive'")|$(run read/list_sources | tr '\n' ' ')" \
    "graph imap jmap |graph||graph imap "
# Both read the distinct sources by a loose scan of bindings_by_handle, a seek
# per source (and per collection store-wide), never a binding each: a drain
# asks once per add, move or copy (§15.2).
expect "sources: collection_sources and list_sources seek the next source above the last, scanning no binding" \
    "$(plan owner/collection_sources ":collection='INBOX'" | grep -c 'SEARCH b USING COVERING INDEX bindings_by_handle (collection=? AND source>?)' || true)$(plan read/list_sources | grep -c 'SEARCH b USING COVERING INDEX bindings_by_handle (collection=? AND source>?)' || true)$({ plan owner/collection_sources ":collection='INBOX'"; plan read/list_sources; } | grep -cE 'SCAN (b|bindings)\b|SEARCH bindings ' || true)" "110"
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
    takes "search/$file" "$@"
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

# A placement names its body by object.id (§3): an upsert takes the body by
# its hash and writes its id, a hash the index does not hold refused, and a
# body's id is drawn above every id drawn before, a deleted body's included,
# so a placement a pass has not yet moved off a deleted body names no other.
fresh
index
body "$h2" > /dev/null
isearch upsert_placement ":collection='C'" ":seq=2" ":link_id='y'" ":hash='$h2'" > /dev/null
isearch delete_object_row ":hash='$h2'"
body "$h3" > /dev/null
expect "index: a placement holds its body's object.id, a hash the index does not hold is refused, and an id is never drawn twice" \
    "$(sqlite3 "$dir/index.db" "SELECT p.object FROM placement p WHERE p.seq = 2;")|$(isearch upsert_placement ":collection='C'" ":seq=3" ":link_id='z'" ":hash='$h4'" 2>&1 | grep -c 'CHECK constraint failed: object > 0')|$(sqlite3 "$dir/index.db" "SELECT id FROM object WHERE hash = '$h3';")|$(isearch placements_gone | grep -c "|y|$")" \
    "1|1|2|1"
# Every join from a body to its placements seeks placement_by_object by the
# body's id, a text term's matches included, never by a name.
expect "index: a body's placements are sought by its id, a text term's matches joining no object row" \
    "$(for statement in match_objects categorised object_placed coverage_all; do isplan "$statement" ":match='\"budget\"'" ":value='work'" ":hash='$h1'" | grep -c 'placement_by_object (object=?)' || true; done | tr -d '\n')|$(isplan match_objects ":match='\"budget\"'" | grep -cE 'SEARCH o |SCAN o |sqlite_autoindex_object_1' || true)|$(for statement in attached holding; do isplan "$statement" ":property='phone'" | grep -c 'SEARCH o USING INTEGER PRIMARY KEY (rowid=?)' || true; done | tr -d '\n')" \
    "1111|0|11"

fresh
index
expect "index: an object names a body as the store does, 52 characters of a-z2-7, never a path, and a placement names none other" \
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

# --- A horizon that rolls re-expands what may gain an occurrence (SEARCH.md §7)

fresh
index
collection INBOX
item INBOX mail 1
run owner/set_collection_kind ":collection='Cal'" ":account=NULL" ":kind='text/calendar'"
for spec in past:2 series:3 ended:4 entering:5 diary:6 gone:7; do
    item Cal "${spec%:*}" "${spec#*:}"
done
sql "UPDATE items SET sort_key = CASE WHEN link_id IN ('entering', 'mail') THEN '2028-09-01T10:00:00Z' ELSE '2020-01-01T10:00:00Z' END;"
for spec in past:0:NULL series:1:NULL ended:1:"'20200601T000000Z'" entering:0:NULL; do
    IFS=: read -r link recurring bound <<<"$spec"
    run owner/upsert_event_summary ":collection='Cal'" ":link_id='$link'" ":uid='$link'" ":summary=''" ":location=NULL" \
        ":dtstart=NULL" ":dtstart_tzid=NULL" ":dtstart_value=NULL" ":dtend=NULL" ":recurring=$recurring" ":until=$bound"
done
for link in diary gone; do
    run owner/upsert_journal_summary ":collection='Cal'" ":link_id='$link'" ":uid='$link'" ":summary=''" \
        ":dtstart=NULL" ":dtstart_tzid=NULL" ":dtstart_value=NULL"
done
sql "UPDATE items SET deleted = 1 WHERE link_id = 'gone';"
isearch init_index_meta ":version=1" ":tokenizer='unicode61 remove_diacritics 0'" ":extraction=1" ":extractor='scenario 1'"
isearch set_horizon ":horizon_start='2025-08-20T12:00:00Z'" ":horizon_end='2028-08-20T12:00:00Z'"
isearch set_tzdb_version ":tzdb_version='2026a'"
old=(":old_start='2025-08-20T12:00:00Z'" ":old_end='2028-08-20T12:00:00Z'")
same=(":tzdb_version='2026a'" ":floating_zone='UTC'")
expect "roll: a series with no bound, a single item entering the window and every live journal, whose summary cannot say it recurs; never an ended series, a single item outside, a tombstone nor a mail" \
    "$(isearch items_to_reexpand "${old[@]}" ":new_start='2025-09-20T12:00:00Z'" ":new_end='2028-09-20T12:00:00Z'" "${same[@]}" | sort | tr '\n' ' ')" \
    "Cal|3 Cal|5 Cal|6 "
expect "roll: a horizon that did not move answers no journal, only the series it had not reached the bound of" \
    "$(isearch items_to_reexpand "${old[@]}" ":new_start='2025-08-20T12:00:00Z'" ":new_end='2028-08-20T12:00:00Z'" "${same[@]}")" "Cal|3"
steps="$(isplan items_to_reexpand "${old[@]}" ":new_start='2025-09-20T12:00:00Z'" ":new_end='2028-09-20T12:00:00Z'" "${same[@]}")"
expect "roll: items_to_reexpand reads the calendar collections, then their live items, never every item of the store" \
    "$(grep -c 'SCAN c\b' <<<"$steps" || true)$(grep -cE 'SEARCH i USING (COVERING )?INDEX [a-z_0-9]+ \(collection=\?\)' <<<"$steps" || true)$(grep -c 'SCAN i\b' <<<"$steps" || true)" "110"

fresh
index
run owner/set_collection_kind ":collection='Cal'" ":account=NULL" ":kind='text/calendar'"
item Cal ev 1
sql "UPDATE items SET sort_key = '2026-09-01T10:00:00Z' WHERE link_id = 'ev';"
run owner/upsert_event_summary ":collection='Cal'" ":link_id='ev'" ":uid='ev'" ":summary='Review'" ":location=NULL" \
    ":dtstart='20260901T120000'" ":dtstart_tzid='Europe/Paris'" ":dtstart_value=NULL" ":dtend=NULL" ":recurring=0" ":until=NULL"
isearch init_index_meta ":version=1" ":tokenizer='unicode61 remove_diacritics 0'" ":extraction=1" ":extractor='scenario 1'"
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
    "$(isearch coverage ":collections='[\"Cal\",\"Docs\"]'")" "text/calendar|1|0|0|0"
expect "coverage: only the query's collections are counted" \
    "$(isearch coverage ":collections='[\"Docs\"]'")|$(isearch coverage ":collections='[\"Cal\",\"Cal2\"]'")" "|text/calendar|2|0|0|0"
hd="$(name hd)"
isearch insert_object ":hash='$hd'" ":status='decrypted'" ":attachment=0" ":tel=0" ":adr=0" ":bday=0" ":photo=0" > /dev/null
isearch upsert_placement ":collection='Cal2'" ":seq=99" ":link_id='later'" ":hash='$hd'" > /dev/null
expect "coverage: a status this version does not know is read as unparseable, the extraction status an open vocabulary" \
    "$(isearch coverage ":collections='[\"Cal2\"]'")" "text/calendar|1|0|1|0"
sqlite3 "$dir/index.db" "DELETE FROM placement WHERE collection = 'Cal2' AND seq = 99; DELETE FROM object WHERE hash = '$hd';"
steps="$(isplan coverage ":collections='[\"Cal\"]'")"
expect "coverage: each collection seeks items_bodiless, never the store's other rows" \
    "$(grep -c 'USING COVERING INDEX items_bodiless (collection=? AND deleted=? AND object=?)' <<<"$steps" || true)$(grep -c 'items_by_object\|SCAN i' <<<"$steps" || true)" "10"
expect "coverage: the bodies not read whole are walked on object_not_ok to their placements, and missing is sought on its key, never every placement nor every object" \
    "$(grep -c 'SCAN o USING COVERING INDEX object_not_ok' <<<"$steps" || true)$(grep -c 'SEARCH p USING INDEX placement_by_object (object=?)' <<<"$steps" || true)$(grep -c 'SEARCH m USING COVERING INDEX sqlite_autoindex_missing_1 (collection=?)' <<<"$steps" || true)$(grep -cE 'SCAN (o|p|m)$' <<<"$steps" || true)" "1110"
every="$(sql "SELECT json_group_array(id) FROM collections;")"
expect "coverage: coverage_all answers what coverage answers bound to every collection" \
    "$(isearch coverage_all)" "$(isearch coverage ":collections='$every'")"
steps="$(isplan coverage_all)"
expect "coverage: coverage_all walks items_bodiless once and binds no slot, never seeking a collection's items nor scanning the store's" \
    "$(grep -c 'items_bodiless' <<<"$steps" || true)$(grep -c 'temp.param\|(collection=?' <<<"$steps" || true)$(grep -cE 'SCAN i$' <<<"$steps" || true)" "100"

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
isearch upsert_placement ":collection='Cal'" ":seq=2" ":link_id='plain'" ":hash='$ha'" > /dev/null
expect "placed: a body a placement names is placed, one its last placement moved off is not, for the refresh to delete" \
    "$(isearch object_placed ":hash='$ha'")$(isearch object_placed ":hash='$hn'")" "10"

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
isearch init_index_meta ":version=1" ":tokenizer='unicode61 remove_diacritics 0'" ":extraction=1" ":extractor='scenario 1'"
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
    "$purges|$((purges + 1))|0|INBOX|1|a|"

# --- An index names its version and shape, and its store (SEARCH.md §2) -----

fresh
index
isearch init_index_meta ":version=1" ":tokenizer='unicode61 remove_diacritics 0'" ":extraction=1" ":extractor='scenario 1'"
expect "index: init_index_meta stamps this draft and the canonical shape, which load_index_meta answers" \
    "$(isearch load_index_meta | cut -d'|' -f10,11)" "search-draft-16|canonical"
expect "index: init_index_meta records the store and the incarnation it is built from" \
    "$(isearch load_index_meta | cut -d'|' -f8,9)" "$(run read/load_change_cursor | cut -d'|' -f3,4)"
run owner/raise_incarnation ":replaced=NULL"
expect "index: a restored store answers another incarnation than the one the index recorded" \
    "$(isearch load_index_meta | cut -d'|' -f9)|$([ "$(run read/load_change_cursor | cut -d'|' -f4)" -gt 1 ] && echo raised)" "1|raised"

# --- A body that cannot be read is tried again (SEARCH.md §4) ---------------

fresh
index
collection INBOX
object "$h1"
item INBOX m 1 "$h1"
isearch init_index_meta ":version=1" ":tokenizer='unicode61 remove_diacritics 0'" ":extraction=1" ":extractor='scenario 1'"
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

# --- Coverage counts what the index could not read (SEARCH.md §8.2) ---------

# Two mailboxes and an address book: INBOX holds a bodiless message, one whose
# blob is gone, a sealed one and one no parser accepted, and a plain one;
# Archive files the sealed one again; Cards holds a card no parser accepted
# and one whose blob went after it was indexed, kept with its body's rows.
for label in sealed broken plain card kept; do
    printf -v "h_$label" '%s' "$(name "$label")"
done
fresh
index
collection INBOX
collection Archive
run owner/set_collection_kind ":collection='Cards'" ":account=NULL" ":kind='text/vcard'"
for hash in "$h1" "$h_sealed" "$h_broken" "$h_plain" "$h_card" "$h_kept"; do
    object "$hash"
done
item INBOX bare 1
item INBOX lost 2 "$h1"
item INBOX sealed 3 "$h_sealed"
item INBOX broken 4 "$h_broken"
item INBOX plain 5 "$h_plain"
item Archive sealed 3 "$h_sealed"
item Cards card 6 "$h_card"
item Cards kept 7 "$h_kept"
isearch init_index_meta ":version=1" ":tokenizer='unicode61 remove_diacritics 0'" ":extraction=1" ":extractor='scenario 1'"
body "$h_sealed" ":status='encrypted'" > /dev/null
body "$h_broken" ":status='unparseable'" > /dev/null
body "$h_plain" > /dev/null
body "$h_card" ":status='unparseable'" > /dev/null
body "$h_kept" > /dev/null
for spec in INBOX:1:bare:NULL INBOX:2:lost:NULL INBOX:3:sealed:"'$h_sealed'" INBOX:4:broken:"'$h_broken'" \
    INBOX:5:plain:"'$h_plain'" Archive:3:sealed:"'$h_sealed'" Cards:6:card:"'$h_card'" Cards:7:kept:"'$h_kept'"; do
    IFS=: read -r collection seq link hash <<<"$spec"
    isearch upsert_placement ":collection='$collection'" ":seq=$seq" ":link_id='$link'" ":hash=$hash" > /dev/null
done
isearch insert_missing ":collection='INBOX'" ":seq=2"
isearch insert_missing ":collection='Cards'" ":seq=7"
expect "coverage: per kind, the bodiless items, the placements recorded missing, and those whose body is recorded unparseable and encrypted, each a count of its own, a body read whole in none" \
    "$(isearch coverage ":collections='[\"INBOX\",\"Archive\",\"Cards\"]'" | sort | tr '\n' ' ')" \
    "message/rfc822|1|1|1|2 text/vcard|0|1|1|0 "
expect "coverage: a body filed twice counts once per placement of the query's collections, and a collection counting none answers no row" \
    "$(isearch coverage ":collections='[\"Archive\"]'")|$(isearch coverage ":collections='[\"INBOX\"]'")|$(isearch coverage ":collections='[\"Nowhere\"]'")" \
    "message/rfc822|0|0|0|1|message/rfc822|1|1|1|1|"
isearch delete_missing ":collection='INBOX'" ":seq=2"
isearch delete_placement ":collection='INBOX'" ":seq=4" > /dev/null
expect "coverage: a placement read at last, and one gone, are counted no more" \
    "$(isearch coverage ":collections='[\"INBOX\"]'")" "message/rfc822|1|0|0|1"

# --- An index records the revisions of its extraction (SEARCH.md §2, §6) ----

expect "extraction: init_index_meta records the revision of the extraction and the indexer's own, which load_index_meta answers last" \
    "$(isearch load_index_meta | cut -d'|' -f13,14)" "1|scenario 1"
isearch set_extraction ":extraction=2" ":extractor='scenario 1'"
expect "extraction: an indexer at another revision records its own once it extracted every held body again, its own extractor's standing" \
    "$(isearch load_index_meta | cut -d'|' -f13,14)" "2|scenario 1"
isearch set_extraction ":extraction=2" ":extractor='other 7'"
expect "extraction: another indexer's own revision is recorded apart, the format's standing" \
    "$(isearch load_index_meta | cut -d'|' -f13,14)" "2|other 7"
expect "extraction: an index states both, neither defaulted nor null" \
    "$(sqlite3 "$dir/index.db" "INSERT INTO index_meta(id, format_version, shape, version, tokenizer, store_id, store_incarnation) VALUES (2, 'x', 'canonical', 1, 't', 's', 1);" 2>&1 | grep -c 'NOT NULL constraint failed: index_meta.extraction')$(sqlite3 "$dir/index.db" "UPDATE index_meta SET extractor = NULL;" 2>&1 | grep -c 'NOT NULL constraint failed: index_meta.extractor')$(sqlite3 "$dir/index.db" "UPDATE index_meta SET extraction = 'two';" 2>&1 | grep -c 'cannot store TEXT value in INTEGER column')" "111"

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
sql "UPDATE items SET deleted = 1, retained_at = '2026-10-01T00:00:00.000Z' WHERE link_id IN ('r@x', 'z@x');"
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
    "INBOX|1|r@x| INBOX|4|z@x| ||w@x z@x "
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
# A hit is `(account, seq)` and carries its placements (SEARCH.md §8.2): one
# row per live placement of the public id in the account, in collection
# order, with its collection's kind, the `kind:` value it answers to and its
# title.
collection Elsewhere "'home'"
collection Solo
item Elsewhere a 1
item Solo a 1
run owner/set_collection_kind ":collection='Cal'" ":account='work'" ":kind='text/calendar'"
item Cal t 4
item Cal bare 5
item Cal old 6
sql "INSERT INTO mail_summary(item, subject) SELECT id, 'Budget' FROM items WHERE collection = 'INBOX' AND link_id = 'a';
     INSERT INTO task_summary(item, summary) SELECT id, 'Call Bob' FROM items WHERE link_id = 't';
     UPDATE items SET deleted = 1, retained_at = '2026-10-01T00:00:00.000Z' WHERE link_id = 'old';"
expect "hit: every live placement of the hit in its account, in collection order, with its kind, its kind value and its title" \
    "$(isearch hit ":account='work'" ":seq=1" | tr '\n' ' ')" \
    "Archive|a||$h1||2|message/rfc822|mail| INBOX|a||$h1||2|message/rfc822|mail|Budget "
expect "hit: another account's placements and those of no account are other hits; a tombstone and a retained row are none" \
    "$(isearch hit ":account='home'" ":seq=1" | cut -d'|' -f1)|$(isearch hit ":account=NULL" ":seq=1" | cut -d'|' -f1)|$(isearch hit ":account='work'" ":seq=2")$(isearch hit ":account='work'" ":seq=6")" \
    "Elsewhere|Solo|"
expect "hit: a calendar item answers the kind value of the table holding its summary, none when no table holds one" \
    "$(isearch hit ":account='work'" ":seq=4" ".nullvalue=NULL" | cut -d'|' -f1,7-9)|$(isearch hit ":account='work'" ":seq=5" ".nullvalue=NULL" | cut -d'|' -f1,7-9)" \
    "Cal|text/calendar|task|Call Bob|Cal|text/calendar|NULL|"
# A hit names no collection, so the read seeks the public id store-wide: the
# one canonical reader of items_by_seq_global, which io-pimdir's own reads of
# a hit (its ends, its thread) share.
expect "hit: the public id is sought on items_by_seq_global, never by a scan of the items" \
    "$(isplan hit ":account='work'" ":seq=1" | grep -c 'SEARCH i USING INDEX items_by_seq_global (seq=?)' || true)$(isplan hit ":account='work'" ":seq=1" | grep -c 'SCAN i\b' || true)" "10"
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
isearch insert_flag ":flag='todo'" ":collection='Work'" ":seq=1"
isearch insert_flag ":flag='\\seen'" ":collection='Work'" ":seq=1"
isearch insert_flag ":flag='todo'" ":collection='Work'" ":seq=2"
expect "flag: flagged answers the placements holding a keyword" \
    "$(isearch flagged ":flag='todo'" | sort | tr '\n' ' ')|$(isearch flagged ":flag='\\seen'")" "Work|1 Work|2 |Work|1"
isearch replace_flags ":collection='Work'" ":seq=1"
expect "flag: replace_flags clears one placement's keywords, another's kept" \
    "$(isearch flagged ":flag='todo'" | tr '\n' ' ')|$(isearch flagged ":flag='\\seen'")" "Work|2 |"
# A system flag is no row of the index (SEARCH §3, §4): items.marks holds it
# and a query reads it there, so the table refuses each of the five by its
# exact bytes, a keyword spelling one in another case taken.
expect "flag: the index refuses a system flag, each of the five, by its exact bytes" \
    "$(for flag in '\Seen' '\Answered' '\Flagged' '\Draft' '\Deleted'; do isearch insert_flag ":flag='$flag'" ":collection='Work'" ":seq=2" 2>&1 | grep -c 'CHECK constraint failed' || true; done | tr -d '\n')|$(isearch flagged ":flag='\\Seen'")" \
    "11111|"
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

# --- A system flag is read from the store as it stands (SEARCH.md §8, §8.2) --

# is: and a tag: naming a system flag read items.marks, never the index's flag
# table, so a flag the store changed and no refresh folded answers as the
# store holds it: the index here holds a placement for every row and no flag
# at all. unread answers the live rows lacking the bit, an unknown set (no
# bit) among them; marked the live rows holding a bit, each of the five.
fresh
index
collection Work "'work'"
collection Archive "'work'"
marked_item() {
    local flags="'$4'"
    [ "$4" != NULL ] || flags=NULL
    run owner/insert_item ":collection='$1'" ":link_id='$2'" ":seq=$3" ":flags=$flags" ":object_hash=NULL" \
        ":sort_key='2026-09-0${3}T00:00:00Z'" ":level=1" ":deleted=0" ":conflicted=0" ":conflict_object=NULL"
    isearch upsert_placement ":collection='$1'" ":seq=$3" ":link_id='$2'" ":hash=NULL" > /dev/null
}
marked_item Work a 1 '["\\Seen", "\\Flagged"]'
marked_item Archive a 1 '[]'
marked_item Work b 2 '[]'
marked_item Work u 3 NULL
marked_item Work d 4 '["\\Seen", "\\Answered", "\\Draft", "\\Deleted"]'
marked_item Work k 5 '["$todo", "\\seen"]'
expect "flags: unread answers the live rows lacking \\Seen, an unknown set among them, from the store with no flag row in the index" \
    "$(sqlite3 "$dir/index.db" "SELECT count(*) FROM flag;")|$(isearch unread | sort | tr '\n' ' ')" \
    "0|Archive|1 Work|2 Work|3 Work|5 "
expect "flags: marked answers the live rows holding a bit, for each of the five" \
    "$(for mark in 1 2 4 8 16; do isearch marked ":mark=$mark" | sort | tr '\n' ' '; echo -n '/'; done)" \
    "Work|1 Work|4 /Work|4 /Work|1 /Work|4 /Work|4 /"
# A flag changed in the store and not yet folded: no refresh runs between the
# write and the read, and both statements answer the store's state.
run owner/update_item ":collection='Work'" ":link_id='a'" ":flags='[]'" ":object_hash=NULL" ":sort_key='2026-09-01T00:00:00Z'" \
    ":level=1" ":deleted=0" ":conflicted=0" ":conflict_object=NULL" > /dev/null
sql "UPDATE items SET deleted = 1 WHERE link_id = 'b';"
expect "flags: a flag changed and a row deleted since the last refresh answer as the store holds them" \
    "$(isearch unread | sort | tr '\n' ' ')|$(isearch marked ":mark=1" | tr '\n' ' ')|$(isearch marked ":mark=4")" \
    "Archive|1 Work|1 Work|3 Work|5 |Work|4 |"
expect "flags: unread walks items_unread, marked items_by_sort alone, neither the whole table" \
    "$(isplan unread | grep -c 'SCAN i USING INDEX items_unread' || true)$(isplan unread | grep -cE 'SCAN i$|items_by_sort' || true)$(isplan marked ":mark=4" | grep -c 'SCAN i USING COVERING INDEX items_by_sort' || true)$(isplan marked ":mark=4" | grep -cE 'SCAN i$|items_unread' || true)" \
    "1010"

# --- Erasing: a purge leaves nothing in the files (STORAGE.md §11.5) ----------

# erase <secure_delete> <merge>: a mail whose key, subject, body words, body and
# property no other row holds, beside one that stays, purged as §11.5 runs it,
# its properties going with its last row (§4.3), its index rows deleted, the
# text merged by optimize_text when merge is 1, its body collected; answers how
# often its word is left in pimdir.db, then in index.db, then how often its
# body's name is left in pimdir.db, on the object row or objects_by_hash.

erase() {
    secure_delete="$1"
    fresh
    index
    collection INBOX
    for spec in 1:kept 2:zanzibar; do
        IFS=: read -r seq word <<<"$spec"
        mail INBOX "$word@x" "$seq" "$seq" "'2026-09-0${seq}T00:00:00Z'"
        label="h$seq"
        object "${!label}"
        sql "UPDATE items SET object = (SELECT id FROM objects WHERE hash = '${!label}') WHERE link_id = '$word@x';"
        id="$(body "${!label}")"
        text "$id" "$word report" "$word minutes"
        isearch upsert_placement ":collection='INBOX'" ":seq=$seq" ":link_id='$word@x'" ":hash='${!label}'" > /dev/null
    done
    run owner/recompute_refcounts
    run owner/add_property ":seq=2" ":key='x/note'" ":value='zanzibar property'"
    run owner/delete_item_bindings ":collection='INBOX'" ":link_id='zanzibar@x'"
    run owner/retain_item ":collection='INBOX'" ":link_id='zanzibar@x'" ":source='imap'"
    run owner/purge_item ":collection='INBOX'" ":seq=2" > /dev/null
    run owner/release_pins ":hashes='[\"$h2\"]'"
    run owner/delete_garbage_objects
    isearch delete_placement ":collection='INBOX'" ":seq=2" > /dev/null
    isearch delete_object ":rowid=$id"
    isearch delete_object_row ":hash='$h2'"
    [ "$2" = 0 ] || isearch optimize_text
    echo "$(grep -ao zanzibar "$dir/pimdir.db" | wc -l)|$(grep -ao zanzibar "$dir/index.db" | wc -l)|$(grep -ao "$h2" "$dir/pimdir.db" | wc -l)|$(grep -ao "$h2" "$dir/index.db" | wc -l)"
}
expect "erase: a purged mail's key, subject, address, property and body's name leave pimdir.db,
 and its body's words and name index.db, once secure_delete zeroes what a delete frees and optimize_text merges the full-text segments" \
    "$(erase ON 1)" "0|0|0|0"
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
mail INBOX clean 1 10 NULL '["\\Seen"]' '["\\Seen"]'
mail INBOX seen 2 20 NULL '["\\Seen"]' '[]'
mail INBOX label 3 30 NULL '["$x"]' '[]'
mail INBOX unknown 4 40 NULL '["\\Seen"]' '[]'
mail INBOX bound 5 50 NULL
mail INBOX diverged 6 60 NULL
mail INBOX deleted 7 70 NULL
mail INBOX created 8 80 NULL
mail INBOX edited 9 90 NULL
# Both directions of the keyword comparison (SYNC.md §3): a keyword the item
# holds and the base lacks, one the base holds and the item dropped, two sets
# of one size naming different keywords, and a set holding the same keyword
# and bit on both sides, which owes nothing.
mail INBOX removed 10 91 NULL '[]' '["$x"]'
mail INBOX kept 11 92 NULL '["$x","\\Seen"]' '["\\Seen","$x"]'
mail INBOX swapped 12 93 NULL '["$x"]' '["$y"]'
sql "UPDATE items SET flags_known = 0, marks = 0 WHERE link_id = 'unknown';
     UPDATE bindings SET conflicted = 1 WHERE item IN (SELECT id FROM items WHERE link_id = 'bound');
     UPDATE items SET conflicted = 1 WHERE link_id = 'diverged';
     UPDATE items SET deleted = 1 WHERE link_id = 'deleted';
     UPDATE bindings SET base_present = 0, base_flags_known = 0, base_marks = 0 WHERE item IN (SELECT id FROM items WHERE link_id = 'created');
     UPDATE items SET object = (SELECT id FROM objects WHERE hash = '$h1'), level = 2 WHERE link_id = 'edited';
     INSERT INTO bindings(item, collection, source, handle, base_present) VALUES((SELECT id FROM items WHERE link_id = 'seen'), 'INBOX', 'graph', 'g20', 1);"
# The delivered creates (SYNC.md §2): based under a provisional handle, the
# base naming nothing. One holding no body projects Clean and owes nothing;
# one holding the staged body is named, a base naming no body differing from
# every body, the projection then deriving nothing for it (SYNC.md §5); one
# tombstoned since is named as every tombstone is, its Remove held.
for key in dbare dbody dgone; do
    sql "INSERT INTO items(collection, link_id, seq, flags_known, marks, level) VALUES('INBOX', '$key', (SELECT max(seq) + 1 FROM items), 1, 1, 1);
         INSERT INTO bindings(item, collection, source, handle, base_present) VALUES((SELECT id FROM items WHERE link_id = '$key'), 'INBOX', 'imap', char(1) || '$key', 1);"
done
sql "UPDATE items SET object = (SELECT id FROM objects WHERE hash = '$h1'), level = 2 WHERE link_id = 'dbody';
     UPDATE items SET deleted = 1 WHERE link_id = 'dgone';"
run owner/recompute_refcounts
# owing: the handles the statement names, U+0001 written ^A whether the shell
# prints a control character so or raw.
owing() {
    run owner/list_owing_bindings ":collection='INBOX'" ":source='imap'" | sed 's/\x01/^A/g'
}
# Every projected status (SYNC.md §3), by link id: Clean (clean, kept, the
# unknown set, dbare) is never named; Dirty by a system flag (seen), by a
# keyword either way (label, removed, swapped) and by a body (edited),
# Conflict by the binding (bound) and by the item (diverged), Tombstone
# (deleted, dgone), Created (created) and the delivered create holding a body
# (dbody) are, and nothing else.
expect "owing: every projected status, the binding named when its placement is Dirty, Conflict, Tombstone or Created, a delivered create when it holds a body or a tombstone, never when Clean" \
    "$(sql "SELECT group_concat(link_id, ' ') FROM (SELECT i.link_id FROM items i JOIN bindings b ON b.item = i.id
            WHERE b.source = 'imap' AND replace(b.handle, char(1), '^A') IN ($(owing | sed "s/.*/'&'/" | paste -sd,)) ORDER BY i.link_id);")|$(run owner/list_owing_bindings ":collection='INBOX'" ":source='graph'" | tr '\n' ' ')" \
    "bound created dbody deleted dgone diverged edited label removed seen swapped|"
expect "owing: the handles in byte order, a provisional one before every member's" \
    "$(owing | tr '\n' ' ')" "^Adbody ^Adgone 20 30 50 60 70 80 90 91 93 "
expect "lacking: the live items holding a body a source binds not" \
    "$(run owner/list_lacking_items ":collection='INBOX'" ":source='graph'" | tr '\n' ' ')|$(run owner/list_lacking_items ":collection='INBOX'" ":source='imap'" | tr '\n' ' ')" \
    "dbody edited |"
expect "owing: the source's bindings seek bindings_by_handle, never the whole store" \
    "$(plan owner/list_owing_bindings ":collection='INBOX'" ":source='imap'" | grep -c 'bindings_by_handle (collection=? AND source=?)' || true)" "1"
# The two flag sets are compared by a seek each way on the other's key, in
# the delta's read and in the eviction holding the same comparison (§11.3):
# no temporary b-tree is built per binding to compare them.
for statement in list_owing_bindings evict_before; do
    steps="$(plan "owner/$statement" ":collection='INBOX'" ":source='imap'" ":before='2026-09-01T00:00:00Z'")"
    expect "owing: $statement compares the flag sets by two anti-joins on their keys, building no temporary b-tree" \
        "$(grep -c 'SEARCH g USING PRIMARY KEY (item=? AND source=? AND flag=?)' <<<"$steps" || true)$(grep -c 'SEARCH f USING PRIMARY KEY (item=? AND flag=?)' <<<"$steps" || true)$(grep -c 'TEMP B-TREE' <<<"$steps" || true)" "110"
done

# --- The sender rule runs once per page (STORAGE.md §14.2) ------------------

fresh
collection INBOX
run owner/set_collection_kind ":collection='Cards'" ":account=NULL" ":kind='text/vcard'"
mail INBOX m1 1 10 NULL
mail INBOX m2 2 20 NULL
mail INBOX m3 3 30 NULL
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

# --- An item keeps local state, keyed by its public id (§4.3, §9.1, §11) ----

# prop <seq> <key> <value>: add_property, answering the refusal it meets, the
# schema's CHECK or one of its triggers, or nothing when it is taken.
prop() {
    run owner/add_property ":seq=$1" ":key='$2'" ":value='$3'" 2>&1 |
        grep -o 'CHECK constraint failed\|no item holds the seq\|a key holds 64 values' | head -n 1 || true
}
props() {
    run read/list_item_properties ":seq=$1" | tr '\n' ' '
}

fresh
collection INBOX
collection Archive
mail INBOX a 1 10 "'2026-08-01T10:00:00Z'" '["\\Seen"]' '["\\Seen"]'
mail Archive a 1 11 "'2026-08-01T10:00:00Z'" '["\\Seen"]' '["\\Seen"]'
mail INBOX b 2 12 "'2026-08-02T10:00:00Z'"
owing="$(run owner/list_owing_bindings ":collection='INBOX'" ":source='imap'")|$(run owner/list_lacking_items ":collection='INBOX'" ":source='imap'")"
loaded="$(run owner/load_items ":collection='INBOX'")"
cursor="$(run read/load_change_cursor | cut -d'|' -f1)"
run queue/enqueue_action ":producer='p'" ":collection='INBOX'" ":action='set-property'" ":payload='{\"v\":1,\"seq\":1,\"key\":\"pimdir/label\",\"add\":[\"Receipts\"]}'" ":target_collection=NULL" ":object_hash=NULL"
id="$(run owner/list_pending_actions | cut -d'|' -f1)"
run owner/claim_action ":id=$id" > /dev/null
run owner/add_property ":seq=1" ":key='pimdir/label'" ":value='Receipts'"
run owner/record_receipt ":id=$id" ":collection='INBOX'" ":seq=1"
expect "property: a set-property applied leaves the value under the seq, read whatever collection files it, and its receipt" \
    "$(props 1)|$(run read/load_receipt ":id=$id" | cut -d'|' -f2,3)" "pimdir/label|Receipts |INBOX|1"
expect "property: a value added stamps every row holding the seq, in every collection" \
    "$(run read/list_items_changed_since ":since=$cursor" ":limit=10" | cut -d'|' -f1,2 | sort | tr '\n' ' ')" "Archive|a INBOX|a "
expect "property: a property derives no push and moves nothing a load compares but the stamp (SYNC.md §3)" \
    "$(run owner/list_owing_bindings ":collection='INBOX'" ":source='imap'")|$(run owner/list_lacking_items ":collection='INBOX'" ":source='imap'")|$(run owner/load_items ":collection='INBOX'")" \
    "$owing|$loaded"
cursor="$(run read/load_change_cursor | cut -d'|' -f1)"
run owner/add_property ":seq=1" ":key='pimdir/label'" ":value='Receipts'"
run owner/remove_property ":seq=1" ":key='pimdir/label'" ":value='absent'"
expect "property: a value added again, or one removed that is not held, moves no row and stamps nothing" \
    "$(run read/list_items_changed_since ":since=$cursor" ":limit=10")|$(props 1)" "|pimdir/label|Receipts "
run owner/remove_property ":seq=1" ":key='pimdir/label'" ":value='Receipts'"
expect "property: a value removed stamps every row holding the seq" \
    "$(run read/list_items_changed_since ":since=$cursor" ":limit=10" | cut -d'|' -f1,2 | sort | tr '\n' ' ')|$(props 1)" "Archive|a INBOX|a |"

key64="a/$(printf '%062d' 0)"
expect "property: the schema refuses a key past its bounds: uppercase, no namespace, an empty part, three parts, a space, 65 bytes; 64 bytes and every character a part takes are taken" \
    "$(for key in Pimdir/label label /x x/ a/b/c 'a b/c' "${key64}0" "$key64" x.y_z-0/a.b_c-9; do echo "[$(prop 2 "$key" v)]"; done | tr -d '\n')" \
    "[CHECK constraint failed][CHECK constraint failed][CHECK constraint failed][CHECK constraint failed][CHECK constraint failed][CHECK constraint failed][CHECK constraint failed][][]"
expect "property: the schema refuses a value past its bounds: empty, 1,025 bytes of ASCII, 1,026 bytes in 513 characters, a NUL; 1,024 bytes in either are taken" \
    "$(for value in '' "$(printf 'a%.0s' $(seq 1025))" "$(printf 'é%.0s' $(seq 513))" "$(printf 'a%.0s' $(seq 1024))" "$(printf 'é%.0s' $(seq 512))"; do echo "[$(prop 2 x/y "$value")]"; done | tr -d '\n')|$(sql "INSERT INTO item_property(seq, key, value) VALUES(2, 'x/y', 'a' || char(0) || 'b');" 2>&1 | grep -c 'CHECK constraint failed')" \
    "[CHECK constraint failed][CHECK constraint failed][CHECK constraint failed][][]|1"
expect "property: a seq no row of items holds takes none" "$(prop 99 x/y v)" "no item holds the seq"
sql "WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 64) INSERT INTO item_property(seq, key, value) SELECT 2, 'x/many', 'v' || i FROM n;"
expect "property: 64 values under one key are taken, the 65th refused, one held added again changing nothing" \
    "$(sql "SELECT count(*) FROM item_property WHERE seq = 2 AND key = 'x/many';")|$(prop 2 x/many v65)|$(prop 2 x/many v1)" "64|a key holds 64 values|"
sql "DELETE FROM item_property WHERE seq = 2;"

prop 1 pimdir/label Receipts
prop 1 pimdir/label 'Tax returns'
prop 2 pimdir/label receipts
prop 2 himalaya/snooze-until 2026-12-01T09:00:00Z
expect "property: the values a key holds, each once in byte order; the live placements holding a key, or one value of it byte for byte" \
    "$(run read/list_property_values ":key='pimdir/label'" | tr '\n' ' ')|$(run read/list_property_holders ":key='pimdir/label'" | tr '\n' ' ')|$(run read/list_value_holders ":key='pimdir/label'" ":value='Receipts'" | tr '\n' ' ')|$(run read/list_value_holders ":key='pimdir/label'" ":value='RECEIPTS'")|$(run read/list_property_values ":key='x/none'")" \
    "Receipts Tax returns receipts |Archive|1 INBOX|1 INBOX|2 |Archive|1 INBOX|1 ||"
expect "property: label: and property: seek the value index, an item's properties its key, a holder its public id" \
    "$(plan read/list_value_holders ":key='k'" ":value='v'" | grep -c 'item_property_by_value (key=? AND value=?)\|items_by_seq_global (seq=?)')|$(plan read/list_property_values ":key='k'" | grep -c 'item_property_by_value (key=?')|$(plan read/list_property_holders ":key='k'" | grep -c 'item_property_by_value (key=?)\|items_by_seq_global (seq=?)')|$(plan read/list_item_properties ":seq=1" | grep -c 'PRIMARY KEY (seq=?)')" \
    "2|2|2|1"
expect "property: the triggers seek the seq: the stamp on items_by_seq_global, the drop on the table's key" \
    "$(trigger_plan item_property_stamp_delete ":old_seq=1" | grep -c 'items_by_seq_global (seq=?)')|$(trigger_plan items_drop_properties ":old_seq=1" | grep -c 'PRIMARY KEY (seq=?)')" "1|1"

run owner/delete_binding ":collection='INBOX'" ":link_id='b'" ":source='imap'"
run owner/insert_binding ":collection='INBOX'" ":link_id='b'" ":source='imap'" ":handle='99'" \
    ":base_flags='[]'" ":base_object=NULL" ":base_revision=NULL" ":base_present=1" \
    ":conflicted=0" ":conflict_revision=NULL" ":conflict_object=NULL" ":shared_object=NULL"
run owner/bump_generation ":collection='INBOX'" > /dev/null
expect "property: a rekey moves the handle under the item, its seq and its properties kept (§12)" \
    "$(run read/seq_by_link ":collection='INBOX'" ":link_id='b'")|$(props 2)" "2|himalaya/snooze-until|2026-12-01T09:00:00Z pimdir/label|receipts "

run owner/delete_item_bindings ":collection='INBOX'" ":link_id='a'"
run owner/retain_item ":collection='INBOX'" ":link_id='a'" ":source='imap'"
expect "property: a retained row keeps the properties, which a trash view reads, and a holder lists live rows alone" \
    "$(props 1)|$(run read/list_value_holders ":key='pimdir/label'" ":value='Receipts'" | tr '\n' ' ')" \
    "pimdir/label|Receipts pimdir/label|Tax returns |Archive|1 "
run owner/purge_item ":collection='INBOX'" ":seq=1" > /dev/null
expect "property: a purge leaving another row of the seq keeps them" \
    "$(props 1)" "pimdir/label|Receipts pimdir/label|Tax returns "
run owner/delete_item_bindings ":collection='Archive'" ":link_id='a'"
run owner/retain_item ":collection='Archive'" ":link_id='a'" ":source='imap'"
run owner/retained_item ":collection='Archive'" ":link_id='a'" > /dev/null
run owner/revive_item ":collection='Archive'" ":link_id='a'"
expect "property: a restore revives the row under its seq, the properties with it" \
    "$(run read/seq_by_link ":collection='Archive'" ":link_id='a'")|$(props 1)" "1|pimdir/label|Receipts pimdir/label|Tax returns "
run owner/retain_item ":collection='Archive'" ":link_id='a'" ":source='imap'"
run owner/purge_item ":collection='Archive'" ":seq=1" > /dev/null
expect "property: the purge of the last row holding the seq takes them, and no other seq's" \
    "$(props 1)|$(sql "SELECT count(*) FROM item_property WHERE seq = 1;")|$(props 2)" \
    "|0|himalaya/snooze-until|2026-12-01T09:00:00Z pimdir/label|receipts "
run owner/delete_collection ":collection='INBOX'"
run owner/recompute_refcounts
expect "property: a collection's delete takes the properties of the last rows it held" \
    "$(sql "SELECT count(*) FROM item_property;")" "0"

# An eviction keeps an item holding a property (§11.3): no relisting would
# restore it, a widening naming the member again under a new seq.
fresh
collection INBOX
mail INBOX kept 1 10 "'2026-08-01T10:00:00Z'"
mail INBOX gone 2 11 "'2026-08-01T10:00:00Z'"
prop 1 himalaya/muted 1
expect "property: an eviction keeps an item whose seq holds a property, its properties with it" \
    "$(run owner/evict_before ":collection='INBOX'" ":before='2026-09-01T00:00:00Z'" | tr '\n' ' ')|$(props 1)" "2 |himalaya/muted|1 "

# --- Every statement runs (AGENTS.md §4) --------------------------------------

# Every statement under queries/ ran in a scenario above, or is waived with its
# reason, one `part/profile/name: reason` a line of the waiver file; a waiver
# naming no statement, or one a scenario runs, fails too, so the list holds
# only what no scenario can run.
ran="$(sort -u "$dir/ran")"
all="$(cd "$root/queries" && find . -name '*.sql' | sed 's|^\./||; s|\.sql$||' | sort)"
waived="$(sed '/^#/d; /^$/d; /^index\//d' "$waivers" | sort)"
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

# --- Every index is read (STORAGE.md §4.3) -------------------------------------

# Every index of the store and of the canonical search index is named by the
# query plan of a canonical statement, its parameters unbound, or is waived
# with its reason, one `index/name: reason` a line of the waiver file: an
# index no statement reads costs every write and serves none. A waiver naming
# no index, or one a plan names, fails too.
fresh
index
plans="$(
    while read -r file; do
        { cat "$root/queries/storage/read/create_param.sql"; echo "EXPLAIN QUERY PLAN"; cat "$file"; } | sqlite3 "$dir/pimdir.db"
    done < <(find "$root/queries/storage" -name '*.sql' | sort)
    while read -r file; do
        { echo "ATTACH '$dir/pimdir.db' AS store;"; cat "$root/queries/storage/read/create_param.sql"
          echo "EXPLAIN QUERY PLAN"; cat "$file"; } | sqlite3 "$dir/index.db"
    done < <(find "$root/queries/search" -name '*.sql' | sort)
)"
indexes="$(for db in pimdir index; do
    sqlite3 "$dir/$db.db" "SELECT name FROM sqlite_schema WHERE type = 'index' AND name NOT LIKE 'sqlite_%';"
done | sort)"
index_waived="$(sed -n 's|^index/||p' "$waivers")"
while read -r name; do
    if grep -qE "INDEX $name( |$)" <<<"$plans"; then
        if grep -q "^$name: " <<<"$index_waived"; then
            echo "index/$name: waived, yet a canonical plan names it" >&2
            failures=$((failures + 1))
        fi
    elif ! grep -q "^$name: ." <<<"$index_waived"; then
        echo "$name: an index no canonical plan names, and waived nowhere" >&2
        failures=$((failures + 1))
    fi
done <<<"$indexes"
while read -r line; do
    [ -n "$line" ] || continue
    if ! grep -qxF "${line%%: *}" <<<"$indexes"; then
        echo "index/${line%%: *}: waived, and no index of the schemas" >&2
        failures=$((failures + 1))
    fi
done <<<"$index_waived"

if [ -s "$dir/stray" ]; then
    echo "a scenario binds a parameter its statement does not take:" >&2
    sort -u "$dir/stray" >&2
    failures=$((failures + 1))
fi

if [ "$failures" -gt 0 ]; then
    echo "$failures invariant(s) broken" >&2
    exit 1
fi

echo "every invariant scenario holds, $(grep -cxF -f <(echo "$all") <<<"$ran") of $(grep -c . <<<"$all") statements run, $(grep -c . <<<"$waived" || true) waived, $(grep -c . <<<"$indexes") indexes read by a plan or waived, $(grep -c . <<<"$index_waived" || true) waived"
