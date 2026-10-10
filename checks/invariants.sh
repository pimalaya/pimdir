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


# plan <profile/name> [:param=literal...]: the statement's query plan, bound.
plan() {
    local file="$1"; shift
    {
        for binding in "$@"; do
            echo ".parameter set ${binding%%=*} ${binding#*=}"
        done
        echo "EXPLAIN QUERY PLAN"
        cat "$root/queries/storage/$file.sql"
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
expect "role: a value outside the kind's vocabulary is refused" \
    "$(fails owner/set_collection_role ":collection='INBOX'" ":role='default'" && echo refused)" "refused"
run owner/set_collection_kind ":collection='Cal'" ":account=NULL" ":kind='text/calendar'"
run owner/set_collection_role ":collection='Cal'" ":role='default'"
expect "role: a calendar is the default one" "$(sql "SELECT role FROM collections WHERE id = 'Cal';")" "default"
run owner/set_collection_role ":collection='Cal'" ":role=NULL"
expect "role: a source no longer saying it clears it" "$(sql "SELECT count(*) FROM collections WHERE role IS NOT NULL;")" "0"
run owner/set_collection_name ":collection='Bare'" ":account=NULL" ":name='Bare'"
expect "role: an undeclared kind takes none" \
    "$(fails owner/set_collection_role ":collection='Bare'" ":role='sent'" && echo refused)" "refused"

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

# --- A producer follows its row to the item it created (§15.2, §15.4) ---------

fresh
collection INBOX
run queue/enqueue_action ":producer='p'" ":collection='INBOX'" ":action='add'" ":payload='{\"v\":1,\"link_id\":\"mid:a\"}'" ":object_hash=NULL"
run queue/enqueue_action ":producer='p'" ":collection='INBOX'" ":action='remove'" ":payload='{\"v\":1,\"seq\":9}'" ":object_hash=NULL"
expect "receipt: a pending row reads as itself, unparked" \
    "$(run read/load_action ":id=1" | cut -d'|' -f1,4,5,8)" "1|INBOX|add|"
run owner/park_action ":id=2" ":error='unknown seq: 9'"
expect "receipt: a parked row reads with its error" \
    "$(run read/load_action ":id=2" | cut -d'|' -f8)" "unknown seq: 9"
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
run queue/enqueue_action ":producer='p'" ":collection='Inbox'" ":action='add'" ":payload='{\"v\":1}'" ":object_hash=NULL"
expect "receipt: a queue id is never reused, so an old receipt names no new row" \
    "$(run read/load_action ":id=3" | cut -d'|' -f1)" "3"

# --- A performed intent leaves a receipt, a withdrawn one none (§15.5) ------

fresh
collection INBOX
collection Sent
object m1
run queue/enqueue_action ":producer='p'" ":collection='INBOX'" ":action='collection-create'" ":payload='{\"v\":1,\"source\":\"imap\",\"name\":\"Projects\"}'" ":object_hash=NULL"
run queue/enqueue_action ":producer='p'" ":collection='INBOX'" ":action='collection-create'" ":payload='{\"v\":1,\"source\":\"imap\",\"name\":\"Other\"}'" ":object_hash=NULL"
run queue/pin_object ":hash='m1'"
run queue/enqueue_action ":producer='p'" ":collection='Sent'" ":action='submit'" ":payload='{\"v\":1,\"copy\":\"Sent\"}'" ":object_hash='m1'"
run owner/cancel_action ":id=1" >/dev/null
run owner/record_receipt ":id=1" ":collection='INBOX'" ":seq=NULL"
run owner/cancel_action ":id=2" >/dev/null
expect "acknowledge: a performed intent reads as applied, naming no item" \
    "$(run read/load_action ":id=1")$(run read/load_receipt ":id=1" | cut -d'|' -f2,3)" "INBOX|"
expect "acknowledge: a withdrawn intent leaves none" \
    "$(run read/load_action ":id=2")$(run read/load_receipt ":id=2")" ""
run queue/pin_object ":hash='m1'"
run queue/enqueue_action ":producer='owner'" ":collection='Sent'" ":action='add'" ":payload='{\"v\":1,\"flags\":[\"\\\\Seen\"]}'" ":object_hash='m1'"
pin="$(run owner/cancel_action ":id=3")"
run owner/record_receipt ":id=3" ":collection='Sent'" ":seq=NULL"
run owner/release_pins ":hashes='[\"$pin\"]'"
expect "acknowledge: a replaced intent reads as applied, its change a row of its own" \
    "$(run read/load_receipt ":id=3" | cut -d'|' -f2)$(run read/load_action ":id=4" | cut -d'|' -f5)" "Sentadd"


# --- Nothing reaches the store unnamed (§10, SYNC.md §4) ---------------------

fresh
expect "probes: the table is gone, every listed member being named" \
    "$(sql "SELECT count(*) FROM sqlite_schema WHERE name = 'probes';")" "0"

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
sql "INSERT INTO items(collection, link_id, seq, flags, level) VALUES('INBOX', 'draft', 5, '[]', 2);
     INSERT INTO bindings(collection, link_id, source, handle) VALUES('INBOX', 'draft', 'imap', char(1) || 'draft');
     INSERT INTO mail_summary(collection, link_id, subject, date) VALUES('INBOX', 'draft', '', '2026-10-06T09:00:00Z');"
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
expect "round: the last page infers deletes in scope only, the undated always in it, never a pending create" \
    "$(run owner/list_unstamped_bindings ":collection='INBOX'" ":source='imap'" | tr '\n' ' ')" "20|nodate 25|gone "
run owner/open_round ":collection='INBOX'" ":source='imap'" ":since='2026-09-01T00:00:00Z'" ":until=NULL" ":band=0"
expect "round: a restart draws a new id, voiding the cursor, the checkpoint and the old stamps" \
    "$(run owner/load_round ":collection='INBOX'" ":source='imap'" | cut -d'|' -f1,5,6)|$(run owner/list_unstamped_bindings ":collection='INBOX'" ":source='imap'" | cut -d'|' -f1 | tr '\n' ' ')" \
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
    "$(run owner/list_unstamped_bindings ":collection='INBOX'" ":source='imap'" | tr '\n' ' ')" "10|old "
run owner/close_round ":collection='INBOX'" ":source='imap'" ":checkpoint=NULL" ":since='2026-07-01T00:00:00Z'" ":until=NULL"
expect "band: closing clears the band with the round" \
    "$(run owner/load_round ":collection='INBOX'" ":source='imap'" | cut -d'|' -f2,7)" "|0"
run owner/open_round ":collection='INBOX'" ":source='imap'" ":since='2026-07-01T00:00:00Z'" ":until=NULL" ":band=0"
expect "band: a round over the whole scope still finds the undated member absent" \
    "$(run owner/list_unstamped_bindings ":collection='INBOX'" ":source='imap'" | tr '\n' ' ')" "10|old 20|nodate 30|recent "

# --- Collecting below a date is manual and pushes nothing (§11.3) -----------

fresh
collection INBOX
collection Archive
object h1
mail INBOX old 1 10 "'2026-08-01T10:00:00Z'"
sql "UPDATE items SET object_hash = 'h1' WHERE link_id = 'old'; UPDATE bindings SET base_object = 'h1' WHERE link_id = 'old';"
mail INBOX dirty 2 11 "'2026-08-01T10:00:00Z'" '["\\Flagged"]' '[]'
mail INBOX recent 3 12 "'2026-10-06T08:00:00Z'"
mail INBOX nodate 4 13 NULL
mail Archive old 1 10 "'2026-08-01T10:00:00Z'"
sql "INSERT INTO items(collection, link_id, seq, flags, level) VALUES('INBOX', 'created', 5, '[]', 2);
     INSERT INTO bindings(collection, link_id, source, handle) VALUES('INBOX', 'created', 'imap', char(1) || 'created');
     INSERT INTO mail_summary(collection, link_id, subject, date) VALUES('INBOX', 'created', '', '2026-08-01T10:00:00Z');"
run owner/recompute_refcounts
purges="$(sql "SELECT purges FROM store_meta;")"
expect "collect: only what owes nothing, below the date, in the collection" \
    "$(run owner/collect_before ":collection='INBOX'" ":before='2026-09-01T00:00:00Z'")" "1"
run owner/recompute_refcounts
expect "collect: an unpushed flag, a pending create, the undated and the newer stay" \
    "$(sql "SELECT link_id FROM items WHERE collection = 'INBOX' ORDER BY link_id;" | tr '\n' ' ')" "created dirty nodate recent "
expect "collect: bindings, summary and addresses go with the item" \
    "$(sql "SELECT (SELECT count(*) FROM bindings WHERE collection = 'INBOX' AND link_id = 'old') + (SELECT count(*) FROM mail_summary WHERE collection = 'INBOX' AND link_id = 'old');")" "0"
expect "collect: the body is released to the collector, the holder elsewhere untouched" \
    "$(sql "SELECT refcount FROM objects WHERE hash = 'h1';")$(sql "SELECT count(*) FROM items WHERE collection = 'Archive';")" "01"
expect "collect: no tombstone, no queued push, and the feed counts a purge" \
    "$(sql "SELECT count(*) FROM items WHERE deleted = 1;")$(sql "SELECT count(*) FROM queue;")$(sql "SELECT purges FROM store_meta;")" "00$((purges + 1))"

# --- Releasing bodies below a date keeps the headers (§11.4) ----------------

fresh
collection INBOX
collection Archive
collection Both
run owner/set_collection_kind ":collection='Cards'" ":account=NULL" ":kind='text/vcard'"
for hash in h1 h2 h3 h4 h5 h6 h7 h8 h9 hc; do object $hash; done
run owner/upsert_checkpoint ":collection='INBOX'" ":source='imap'" ":checkpoint=NULL"
mail INBOX old 1 10 "'2026-08-01T10:00:00Z'"
mail INBOX dirty 2 11 "'2026-08-01T10:00:00Z'" '["\\Flagged"]' '[]'
mail INBOX nodate 3 12 NULL
mail INBOX recent 4 13 "'2026-10-06T08:00:00Z'"
mail INBOX conflicted 5 14 "'2026-08-01T10:00:00Z'"
mail INBOX diverged 6 15 "'2026-08-01T10:00:00Z'"
mail INBOX edited 7 16 "'2026-08-01T10:00:00Z'"
mail INBOX witness 8 17 "'2026-08-01T10:00:00Z'"
mail Archive old 1 10 "'2026-08-01T10:00:00Z'"
mail Both full 9 20 "'2026-08-01T10:00:00Z'"
mail Both half 10 21 "'2026-08-01T10:00:00Z'"
sql "UPDATE items SET sort_key = coalesce((SELECT date FROM mail_summary s WHERE s.collection = items.collection AND s.link_id = items.link_id), ''), level = 2;
     UPDATE items SET object_hash = CASE link_id WHEN 'old' THEN 'h1' WHEN 'dirty' THEN 'h2' WHEN 'nodate' THEN 'h3' WHEN 'recent' THEN 'h4'
         WHEN 'conflicted' THEN 'h5' WHEN 'diverged' THEN 'h6' WHEN 'edited' THEN 'h7' WHEN 'witness' THEN 'h8' ELSE 'h9' END;
     UPDATE bindings SET base_object = (SELECT object_hash FROM items i WHERE i.collection = bindings.collection AND i.link_id = bindings.link_id);
     UPDATE items SET conflicted = 1, conflict_object = 'hc' WHERE link_id = 'conflicted';
     UPDATE bindings SET conflicted = 1 WHERE link_id = 'diverged';
     UPDATE bindings SET base_object = 'h1' WHERE link_id = 'edited';
     UPDATE bindings SET base_present = 0, base_flags = NULL WHERE link_id = 'witness';
     INSERT INTO items(collection, link_id, seq, flags, object_hash, sort_key, level) VALUES
         ('INBOX', 'created', 20, '[]', 'h9', '2026-08-01T10:00:00Z', 2),
         ('INBOX', 'lone', 21, '[]', 'h9', '2026-08-01T10:00:00Z', 2),
         ('Cards', 'card', 22, NULL, 'h9', '2026-08-01', 2);
     INSERT INTO bindings(collection, link_id, source, handle) VALUES('INBOX', 'created', 'imap', char(1) || 'created');
     INSERT INTO bindings(collection, link_id, source, handle, base_present, base_object) VALUES('Cards', 'card', 'dav', 'c', 1, 'h9');
     INSERT INTO bindings(collection, link_id, source, handle, base_flags, base_object, base_present)
         VALUES('Both', 'full', 'graph', 'g20', '[]', 'h9', 1);
     INSERT INTO sources(collection, source) VALUES('Both', 'imap'), ('Both', 'graph');"
run owner/recompute_refcounts
cursor="$(run read/load_change_cursor | cut -d'|' -f1)"
set=":collections='[\"INBOX\",\"Both\",\"Cards\"]'"
run owner/release_bases_before "$set" ":until='2026-09-01T00:00:00Z'"
expect "release: below the date, what needs no body, the undated included, two sources' bases alike" \
    "$(run owner/release_before "$set" ":until='2026-09-01T00:00:00Z'" | sort -n | tr '\n' ' ')" "1 2 3 8 9 "
run owner/recompute_refcounts
expect "release: a conflict, a diverged binding, a local edit, a pending create, no binding, an unbound source, another kind, the newer and an unnamed collection keep theirs" \
    "$(sql "SELECT collection || ':' || link_id FROM items WHERE object_hash IS NOT NULL ORDER BY collection, link_id;" | tr '\n' ' ')" \
    "Archive:old Both:half Cards:card INBOX:conflicted INBOX:created INBOX:diverged INBOX:edited INBOX:lone INBOX:recent "
expect "release: back to Meta, flags, summary and addresses kept" \
    "$(sql "SELECT level, flags FROM items WHERE collection = 'INBOX' AND link_id = 'dirty';")|$(sql "SELECT count(*) FROM mail_summary WHERE collection = 'INBOX' AND link_id IN ('old', 'dirty', 'nodate', 'witness');")" \
    '1|["\\Flagged"]|4'
expect "release: the bases let go of the body, every binding still based, its flags kept" \
    "$(sql "SELECT count(*) FROM bindings WHERE link_id IN ('old', 'dirty', 'nodate', 'witness', 'full') AND collection != 'Archive' AND base_object IS NULL AND base_present = 1;")|$(sql "SELECT base_flags FROM bindings WHERE link_id = 'dirty';")" \
    "6|[]"
expect "release: a body held elsewhere stays pinned, the rest fall to the collector" \
    "$(run owner/list_garbage_objects | sort | tr '\n' ' ')|$(sql "SELECT refcount FROM objects WHERE hash = 'h1';")" "h2 h3 h8 |3"
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
# ref <from_kind> <from_link_id> <to_kind> <to_link_id> <role> <origin>: add_reference.
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
expect "reference: a duplicate records nothing" \
    "$(ref $mail_kind m $card_kind alice sender auto)$(sql "SELECT count(*) FROM item_reference;")" "1"
expect "reference: a person's takes over a rule's, never the reverse" \
    "$(ref $mail_kind m $card_kind alice sender user | cut -d'|' -f6)$(ref $mail_kind m $card_kind alice sender auto)$(sql "SELECT origin FROM item_reference;")" \
    "useruser"
expect "reference: an application's x- role is accepted" \
    "$(ref $card_kind alice $cal_kind ev x-moa-thread user | cut -d'|' -f5)" "x-moa-thread"
expect "reference: a role outside the vocabulary, a bare or capital x-, and an unknown origin are refused" \
    "$(fails owner/add_reference ":from_kind='$card_kind'" ":from_link_id='alice'" ":to_kind='$cal_kind'" ":to_link_id='ev'" ":role='friend'" ":origin='user'" && echo r)$(fails owner/add_reference ":from_kind='$card_kind'" ":from_link_id='alice'" ":to_kind='$cal_kind'" ":to_link_id='ev'" ":role='x-'" ":origin='user'" && echo b)$(fails owner/add_reference ":from_kind='$card_kind'" ":from_link_id='alice'" ":to_kind='$cal_kind'" ":to_link_id='ev'" ":role='X-a'" ":origin='user'" && echo c)$(fails owner/add_reference ":from_kind='$card_kind'" ":from_link_id='alice'" ":to_kind='$cal_kind'" ":to_link_id='ev'" ":role='related'" ":origin='robot'" && echo o)" \
    "rbco"
expect "reference: an endpoint the store holds no row of, under that kind, records nothing" \
    "$(ref $mail_kind m $card_kind ghost related user)$(ref $mail_kind m $cal_kind alice related user)" ""
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
mail INBOX m1 1 10 "'2026-10-06T08:00:00Z'"
mail INBOX m2 2 11 "'2026-10-06T09:00:00Z'"
mail INBOX m3 3 12 "'2026-10-06T10:00:00Z'"
mail INBOX m4 4 13 "'2026-10-06T11:00:00Z'"
mail INBOX m5 5 14 "'2026-10-06T12:00:00Z'"
item Cards c1 6
item Cards c2 7
item Cal ev1 8
sql "INSERT INTO item_address(collection, link_id, role, position, address) VALUES
         ('INBOX', 'm1', 'from', 0, 'alice@example.org'), ('INBOX', 'm2', 'from', 0, 'bob@example.org'),
         ('INBOX', 'm3', 'from', 0, 'alice@example.org'), ('INBOX', 'm1', 'to', 0, 'carol@example.org'),
         ('Cards', 'c1', 'email', 0, 'alice@example.org'), ('Cards', 'c2', 'email', 0, 'carol@example.org');
     UPDATE items SET deleted = 1 WHERE link_id = 'm3';
     UPDATE mail_summary SET invitation = 'ev1' WHERE link_id = 'm4';
     UPDATE mail_summary SET invitation = 'ev2' WHERE link_id = 'm5';"
refs() {
    sql "SELECT from_link_id || '>' || to_link_id || ':' || role || ':' || origin FROM item_reference ORDER BY 1;" | tr '\n' ' '
}
run owner/link_senders_of ":link_id='m1'"
expect "auto: a mail refers to the contact its from address names, never through another role" \
    "$(refs)" "m1>c1:sender:auto "
run owner/link_mail_from ":link_id='c1'"
expect "auto: a contact's backfill takes live mail only" "$(refs)" "m1>c1:sender:auto "
run owner/add_reference ":from_kind='$mail_kind'" ":from_link_id='m2'" ":to_kind='$card_kind'" ":to_link_id='c2'" ":role='sender'" ":origin='user'" >/dev/null
sql "INSERT INTO item_address(collection, link_id, role, position, address) VALUES('Cards', 'c2', 'email', 1, 'bob@example.org');"
run owner/link_mail_from ":link_id='c2'"
expect "auto: an address added brings its history, a person's reference kept as it is" \
    "$(refs)" "m1>c1:sender:auto m2>c2:sender:user "
sql "DELETE FROM item_address WHERE link_id = 'c1';"
run owner/link_mail_from ":link_id='c1'"
expect "auto: an address removed removes nothing" "$(refs)" "m1>c1:sender:auto m2>c2:sender:user "
sql "DELETE FROM item_reference;"
run owner/link_senders_of ":link_id=NULL"
expect "auto: a NULL link id backfills every mail" "$(refs)" "m2>c2:sender:auto "
run owner/link_invitations_of ":link_id='m4'"
run owner/link_invitations_of ":link_id='m5'"
expect "auto: an invitation refers to the calendar item it names, none for one not held yet" \
    "$(refs)" "m2>c2:sender:auto m4>ev1:invitation:auto "
item Cal ev2 9
run owner/link_invitations_to ":link_id='ev2'"
expect "auto: a calendar item synced after its invitation is tied to it" \
    "$(refs)" "m2>c2:sender:auto m4>ev1:invitation:auto m5>ev2:invitation:auto "
run owner/upsert_mail_summary ":collection='INBOX'" ":link_id='m4'" ":message_id='m4'" ":in_reply_to='[]'" \
    ":subject='s m4'" ":sender='alice@example.org'" ":sender_name='Alice'" ":date=NULL" ":size=1" ":attachment=0" ":invitation=NULL"
expect "auto: a write without the body keeps a known invitation" \
    "$(sql "SELECT invitation FROM mail_summary WHERE link_id = 'm4';")" "ev1"
for statement in link_senders_of link_mail_from link_invitations_of; do
    expect "auto: $statement seeks one link id" \
        "$(plan "owner/$statement" ":link_id='m1'" | grep -c 'items_by_link (link_id>? AND link_id<?)' || true)" "1"
done
expect "auto: link_invitations_to seeks the invitation" \
    "$(plan owner/link_invitations_to ":link_id='ev1'" | grep -c 'mail_summary_by_invitation' || true)" "1"

# --- A file stands for an attachment until no reference names it (§14.3) ----

fresh
file_kind=application/octet-stream
collection work/INBOX work
for folder in work/Attachments work/Docs; do
    run owner/set_collection_kind ":collection='$folder'" ":account='work'" ":kind='$file_kind'"
done
object hx
mail work/INBOX m 1 10 "'2026-10-06T08:00:00Z'"
# file <collection> <link_id> <seq> <object|NULL> <name> <part|NULL> [bound]
file() {
    run owner/insert_item ":collection='$1'" ":link_id='$2'" ":seq=$3" ":flags='[]'" ":object_hash=$4" \
        ":sort_key='$(tr '[:upper:]' '[:lower:]' <<<"$5")'" ":level=$([ "$4" = NULL ] && echo 1 || echo 2)" \
        ":deleted=0" ":conflicted=0" ":conflict_object=NULL"
    run owner/upsert_file_summary ":collection='$1'" ":link_id='$2'" ":name='$5'" ":media_type='application/pdf'" \
        ":size=1234" ":part=$6"
    if [ -n "${7:-}" ]; then
        sql "INSERT INTO bindings(collection, link_id, source, handle, base_present) VALUES('$1', '$2', 'dav', '$2', 1);"
    fi
}
file work/Attachments 'part:m#2' 2 NULL Report.pdf "'2'"
file work/Attachments 'part:m#3' 3 NULL photo.jpg "'3'"
file work/Docs local 4 "'hx'" notes.txt NULL
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
file work/Docs 'part:m#2' 2 "'hx'" 'Q3 report.pdf' "'2'"
expect "file: saved to a folder, the stand-in still reads, held by the saved copy's body" \
    "$(run read/list_attachments ":account='work'" ":link_id='m'" | head -1 | cut -d'|' -f2,4,8)" "work/Attachments|Report.pdf|hx"
expect "file: one public id for the stand-in and the saved copy" \
    "$(sql "SELECT count(DISTINCT seq) FROM items WHERE link_id = 'part:m#2';")" "1"
run owner/remove_reference ":from_kind='$mail_kind'" ":from_link_id='m'" ":to_kind='$file_kind'" ":to_link_id='part:m#3'" ":role='attachment'" >/dev/null
expect "file: a stand-in no reference names is collected" \
    "$(sql "SELECT count(*) FROM items WHERE link_id = 'part:m#3';")" "0"
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
    "work/Docs:hx|0"

# --- Readers count and page under the chips (§14.1) --------------------------

fresh
collection INBOX
collection Sent
mail INBOX a 1 1 "'2026-10-06T08:00:00Z'" '["\\Seen"]'
mail INBOX b 2 2 "'2026-10-06T20:00:00Z'"
mail INBOX c 3 3 "'2026-10-05T08:00:00Z'"
mail Sent a 1 1 "'2026-10-06T08:00:00Z'" '["\\Seen"]'
sql "UPDATE items SET sort_key = (SELECT date FROM mail_summary s WHERE s.collection = items.collection AND s.link_id = items.link_id);
     UPDATE mail_summary SET attachment = 1, subject = 'Invoice 100%' WHERE link_id = 'c';
     UPDATE items SET flags = NULL WHERE link_id = 'b';"
expect "count: over a set of collections" \
    "$(run read/count_mail ":collections='[\"INBOX\",\"Sent\"]'" ":seen=NULL" ":attachment=NULL")" "4"
expect "count: the read chip, unknown flags unread" \
    "$(run read/count_mail ":collections='[\"INBOX\"]'" ":seen=0" ":attachment=NULL")$(run read/count_mail ":collections='[\"INBOX\"]'" ":seen=1" ":attachment=NULL")" "21"
expect "count: the attachment chip" \
    "$(run read/count_mail ":collections='[\"INBOX\"]'" ":seen=NULL" ":attachment=1")" "1"
expect "count: per day, on the reader's clock" \
    "$(run read/count_mail_by_day ":collections='[\"INBOX\"]'" ":seen=NULL" ":attachment=NULL" ":shift='+300 minutes'" | tr '\n' ' ')" \
    "2026-10-07|1 2026-10-06|1 2026-10-05|1 "
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
sql "UPDATE mail_summary SET size = CASE link_id WHEN 'a' THEN 100 WHEN 'c' THEN 50 END WHERE collection = 'INBOX';"
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

for statement in list_mail_page_filtered search_mail; do
    steps="$(plan "read/$statement" ":collections='[\"INBOX\",\"Sent\"]'" ":pattern='%a%'" ":seen=NULL" \
        ":attachment=NULL" ":after_key=NULL" ":after_seq=NULL" ":after_collection=NULL" ":limit=10")"
    expect "page: $statement walks items_by_sort_global over two collections, sorting nothing" \
        "$(grep -c 'USING INDEX items_by_sort_global' <<<"$steps" || true)$(grep -c 'TEMP B-TREE FOR ORDER BY' <<<"$steps" || true)" "10"
done

expect "since: the page seeks the floor on items_by_sort_global" \
    "$(plan read/list_mail_page_filtered "$both" ":since='2026-10-06T00:00:00Z'" | grep -c 'items_by_sort_global (sort_key>?)' || true)" "1"
for statement in count_mail count_mail_by_day count_unread; do
    expect "since: $statement seeks the floor on items_by_sort" \
        "$(plan "read/$statement" "$both" ":since='2026-10-06T00:00:00Z'" | grep -c 'items_by_sort (collection=? AND sort_key>?)' || true)" "1"
done
expect "sum: both bounds seek items_by_sort, open or not" \
    "$(plan read/sum_mail "$both" ":since=NULL" ":until=NULL" | grep -c 'items_by_sort (collection=? AND sort_key>? AND sort_key<?)' || true)" "1"

if [ "$failures" -gt 0 ]; then
    echo "$failures invariant(s) broken" >&2
    exit 1
fi

echo "every invariant scenario holds"
