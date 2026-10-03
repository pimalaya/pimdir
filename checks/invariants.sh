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

# --- A performed intent replaced by the change it leaves (§15.5) ------------

fresh
collection Sent
object m1
run queue/pin_object ":hash='m1'"
run queue/enqueue_action ":producer='p'" ":collection='Sent'" ":action='submit'" ":payload='{\"v\":1,\"copy\":\"Sent\"}'" ":object_hash='m1'"
run queue/pin_object ":hash='m1'"
run queue/enqueue_action ":producer='owner'" ":collection='Sent'" ":action='add'" ":payload='{\"v\":1,\"flags\":[\"\\\\Seen\"]}'" ":object_hash='m1'"
pin="$(run owner/cancel_action ":id=1")"
run owner/release_pins ":hashes='[\"$pin\"]'"
run owner/delete_garbage_objects
expect "replace: the copy keeps the body the intent pinned" \
    "$(sql "SELECT refcount FROM objects WHERE hash = 'm1';")$(sql "SELECT action FROM queue;")" "1add"

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
sql "INSERT INTO bindings(collection, link_id, source, handle) VALUES('INBOX', 'a', 'graph', '1');"
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

if [ "$failures" -gt 0 ]; then
    echo "$failures invariant(s) broken" >&2
    exit 1
fi

echo "every invariant scenario holds"
