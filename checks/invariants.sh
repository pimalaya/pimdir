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

# --- The agreed body stays pinned until its binding agrees again (§5) ------

fresh
run owner/set_collection_kind ":collection='Cards'" ":account=NULL" ":kind='text/vcard'"
object c1
object c2
item Cards card 1 "'c2'"
run owner/insert_binding ":collection='Cards'" ":link_id='card'" ":source='a'" ":handle='a.vcf'" \
    ":base_flags='[]'" ":base_object='c2'" ":base_revision='r2'" ":base_present=1" \
    ":conflicted=0" ":conflict_revision=NULL" ":conflict_object=NULL" ":shared_object='c2'"
run owner/insert_binding ":collection='Cards'" ":link_id='card'" ":source='b'" ":handle='b.vcf'" \
    ":base_flags='[]'" ":base_object=NULL" ":base_revision='r9'" ":base_present=1" \
    ":conflicted=0" ":conflict_revision=NULL" ":conflict_object=NULL" ":shared_object='c1'"
run owner/recompute_refcounts
expect "shared: the body a binding last agreed with is counted, alone" \
    "$(sql "SELECT refcount FROM objects WHERE hash = 'c1';")|$(run owner/list_garbage_objects)" "1|"
run owner/set_collection_kind ":collection='Emptied'" ":account=NULL" ":kind='text/vcard'"
item Emptied card 1
run owner/insert_binding ":collection='Emptied'" ":link_id='card'" ":source='a'" ":handle='e.vcf'" \
    ":base_flags='[]'" ":base_object=NULL" ":base_revision='r2'" ":base_present=1" \
    ":conflicted=0" ":conflict_revision=NULL" ":conflict_object=NULL" ":shared_object='c1'"
expect "shared: a collection holding only an agreed body holds an object" \
    "$(run owner/collection_holds_objects ":collection='Emptied'")" "1"
expect "shared: the agreed body cannot be deleted under it" \
    "$(sql "DELETE FROM objects WHERE hash = 'c1';" 2>&1 | grep -c 'FOREIGN KEY')" "1"
run owner/delete_collection ":collection='Emptied'"
run owner/update_binding ":collection='Cards'" ":link_id='card'" ":source='b'" \
    ":base_flags='[]'" ":base_object='c2'" ":base_revision='r10'" ":base_present=1" \
    ":conflicted=0" ":conflict_revision=NULL" ":conflict_object=NULL" ":shared_object='c2'"
run owner/recompute_refcounts
expect "shared: once the binding agrees again, the old body falls to the collector" \
    "$(run owner/list_garbage_objects)|$(sql "SELECT refcount FROM objects WHERE hash = 'c2';")" "c1|5"

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
collection Outbox
object m9
run queue/pin_object ":hash='m9'"
run queue/enqueue_action ":producer='p'" ":collection='Outbox'" ":action='submit'" ":payload='{\"v\":1,\"source\":\"smtp\"}'" ":object_hash='m9'"
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
expect "level: the ladder is 1 and 2, an earlier draft's 0 refused" \
    "$(fails owner/insert_item ":collection='Bare'" ":link_id='a'" ":seq=1" ":flags='[]'" ":object_hash=NULL" ":sort_key=''" ":level=0" ":deleted=0" ":conflicted=0" ":conflict_object=NULL" && echo refused)" "refused"
expect "vocabulary: conflict and support outside their sets are refused" \
    "$(sql "UPDATE collections SET conflict = 'newest' WHERE id = 'Bare';" 2>&1 | grep -c CHECK)$(fails owner/set_capability ":account=NULL" ":source='s'" ":collection=NULL" ":capability='mail.message.add'" ":support='some'" ":detail=NULL" && echo refused)" "1refused"

# --- A migration stamps its version; a revision is never lowered (§6) -------

rm -f "$dir/pimdir.db"
sqlite3 "$dir/pimdir.db" "BEGIN; $(cat "$root/migrations/storage/0001_init.sql") PRAGMA user_version = 1; COMMIT;"
run owner/init_store_meta ":version=1" ":hash_algo='blake3'" ":derivation=2"
expect "version: init_store_meta stamps version 1 and the creator's Annex A revision" \
    "$(run read/load_store_meta | cut -d'|' -f1,2,3,8)" "pimdir|1|blake3|2"
run owner/set_store_version ":version=2"
expect "version: a migration's stamp moves store_meta.version" \
    "$(run read/load_store_meta | cut -d'|' -f2)" "2"
run owner/set_derivation ":derivation=3"
run owner/set_derivation ":derivation=1"
expect "derivation: a later revision is recorded, an earlier one never lowers it" \
    "$(run read/load_store_meta | cut -d'|' -f8)" "3"

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


# --- A calendar refusing tasks says so, before its first sync (§15.6) -------

fresh
collection Events
collection Tasks
# NOTE: a source registers each calendar it lists with no checkpoint, so its
# declaration is read before the first item sync binds anything there.
run owner/upsert_checkpoint ":collection='Events'" ":source='caldav'" ":checkpoint=NULL"
run owner/upsert_checkpoint ":collection='Tasks'" ":source='caldav'" ":checkpoint=NULL"
run owner/set_capability ":account=NULL" ":source='caldav'" ":collection='Events'" ":capability='x-vtodo'" ":support='none'" ":detail='VEVENT only'"
expect "x-vtodo: a listed calendar never synced refuses tasks by its row" \
    "$(run read/load_capabilities ":collection='Events'" | grep x-vtodo)" "caldav|x-vtodo|none|VEVENT only"
expect "x-vtodo: a calendar with no row states nothing by it" \
    "$(run read/load_capabilities ":collection='Tasks'" | grep -c x-vtodo)" "0"
run owner/set_capability ":account=NULL" ":source='caldav'" ":collection=NULL" ":capability='x-vtodo'" ":support='none'" ":detail='events only'"
run owner/set_capability ":account=NULL" ":source='caldav'" ":collection='Tasks'" ":capability='x-vtodo'" ":support='full'" ":detail=NULL"
expect "x-vtodo: a calendar stating full wins over a source-wide none" \
    "$(run read/load_capabilities ":collection='Tasks'" | grep x-vtodo)" "caldav|x-vtodo|full|"
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
run owner/set_round_cursor ":collection='INBOX'" ":source='imap'" ":cursor=NULL" ":checkpoint=x'6335'"
expect "round: a delta head lands its checkpoint and keeps the cursor a page landed" \
    "$(run owner/load_round ":collection='INBOX'" ":source='imap'" | cut -d'|' -f5,6)" "p2|c5"
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
mail INBOX gone 11 18 "'2026-08-01T10:00:00Z'"
mail Archive old 1 10 "'2026-08-01T10:00:00Z'"
mail Both full 9 20 "'2026-08-01T10:00:00Z'"
mail Both half 10 21 "'2026-08-01T10:00:00Z'"
sql "UPDATE items SET sort_key = coalesce((SELECT date FROM mail_summary s WHERE s.collection = items.collection AND s.link_id = items.link_id), ''), level = 2;
     UPDATE items SET object_hash = CASE link_id WHEN 'old' THEN 'h1' WHEN 'dirty' THEN 'h2' WHEN 'nodate' THEN 'h3' WHEN 'recent' THEN 'h4'
         WHEN 'conflicted' THEN 'h5' WHEN 'diverged' THEN 'h6' WHEN 'edited' THEN 'h7' WHEN 'witness' THEN 'h8' ELSE 'h9' END;
     UPDATE bindings SET base_object = (SELECT object_hash FROM items i WHERE i.collection = bindings.collection AND i.link_id = bindings.link_id),
         shared_object = (SELECT object_hash FROM items i WHERE i.collection = bindings.collection AND i.link_id = bindings.link_id);
     UPDATE items SET conflicted = 1, conflict_object = 'hc' WHERE link_id = 'conflicted';
     UPDATE bindings SET conflicted = 1 WHERE link_id = 'diverged';
     UPDATE bindings SET base_object = 'h1' WHERE link_id = 'edited';
     UPDATE bindings SET base_present = 0, base_flags = NULL WHERE link_id = 'witness';
     UPDATE items SET deleted = 1 WHERE link_id = 'gone';
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
expect "release: a conflict, a diverged binding, a local edit, a pending create, no binding, an unbound source, another kind, a tombstone, the newer and an unnamed collection keep theirs" \
    "$(sql "SELECT collection || ':' || link_id FROM items WHERE object_hash IS NOT NULL ORDER BY collection, link_id;" | tr '\n' ' ')" \
    "Archive:old Both:half Cards:card INBOX:conflicted INBOX:created INBOX:diverged INBOX:edited INBOX:gone INBOX:lone INBOX:recent "
expect "release: a tombstone, a newer item, a conflicted one and another kind keep their bases" \
    "$(sql "SELECT count(*) FROM bindings WHERE link_id IN ('gone', 'recent', 'conflicted', 'card') AND base_object IS NOT NULL;")|$(sql "SELECT object_hash FROM items WHERE link_id = 'gone';")" "4|h9"
expect "release: back to Meta, flags, summary and addresses kept" \
    "$(sql "SELECT level, flags FROM items WHERE collection = 'INBOX' AND link_id = 'dirty';")|$(sql "SELECT count(*) FROM mail_summary WHERE collection = 'INBOX' AND link_id IN ('old', 'dirty', 'nodate', 'witness');")" \
    '1|["\\Flagged"]|4'
expect "release: a shared body naming the released body lets go of it, another stays" \
    "$(sql "SELECT count(*) FROM bindings WHERE link_id IN ('old', 'dirty', 'nodate', 'witness') AND collection = 'INBOX' AND shared_object IS NULL;")|$(sql "SELECT shared_object FROM bindings WHERE link_id = 'edited';")" "4|h7"
expect "release: the bases let go of the body, every binding still based, its flags kept" \
    "$(sql "SELECT count(*) FROM bindings WHERE link_id IN ('old', 'dirty', 'nodate', 'witness', 'full') AND collection != 'Archive' AND base_object IS NULL AND base_present = 1;")|$(sql "SELECT base_flags FROM bindings WHERE link_id = 'dirty';")" \
    "6|[]"
expect "release: a body held elsewhere stays pinned, the rest fall to the collector" \
    "$(run owner/list_garbage_objects | sort | tr '\n' ' ')|$(sql "SELECT refcount FROM objects WHERE hash = 'h1';")" "h2 h3 h8 |4"
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
sql "INSERT INTO item_address(collection, link_id, role, position, address) VALUES
         ('INBOX', 'm1', 'from', 0, 'alice@example.org'), ('INBOX', 'm2', 'from', 0, 'bob@example.org'),
         ('INBOX', 'm3', 'from', 0, 'alice@example.org'), ('INBOX', 'm1', 'to', 0, 'carol@example.org'),
         ('INBOX', 'alt:Alert|2026-08-01T10:00:00Z|cron@host', 'from', 0, 'alice@example.org'),
         ('Cards', 'c1', 'email', 0, 'alice@example.org'), ('Cards', 'c2', 'email', 0, 'carol@example.org'),
         ('Cards', 'c3', 'email', 0, 'alice@example.org');
     UPDATE items SET deleted = 1 WHERE link_id IN ('m3', 'm6', 'c3', 'ev3');
     UPDATE mail_summary SET invitation = 'ev1' WHERE link_id IN ('m4', 'm6');
     UPDATE mail_summary SET invitation = 'ev2' WHERE link_id = 'm5';
     UPDATE mail_summary SET invitation = 'ev3' WHERE link_id = 'm7';
     UPDATE mail_summary SET invitation = 'ev4' WHERE link_id = 'm8';"
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
sql "INSERT INTO item_address(collection, link_id, role, position, address) VALUES('Cards', 'c2', 'email', 1, 'bob@example.org');"
run owner/link_mail_from ":link_id='c2'"
expect "auto: an address added brings its history, a person's reference kept as it is" \
    "$(refs)" "m1>c1:sender:auto m2>c2:sender:user "
sql "DELETE FROM item_address WHERE link_id = 'c1';"
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
    "$(sql "SELECT invitation FROM mail_summary WHERE link_id = 'm4';")" "ev1"
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
run owner/set_collection_role ":collection='work/Attachments'" ":role='attachments'"
expect "file: the attachments role marks a file collection" \
    "$(sql "SELECT role FROM collections WHERE id = 'work/Attachments';")" "attachments"
expect "file: every stand-in of an account with its message, newest first, paged" \
    "$(run read/list_attachments_by_account ":account='work'" ":after_key=NULL" ":after_seq=NULL" ":limit=10" | cut -d'|' -f3,8,12 | tr '\n' ' ')|$(run read/list_attachments_by_account ":account='work'" ":after_key=''" ":after_seq=3" ":limit=10" | cut -d'|' -f3)" \
    "part:m#3|m|alice@example.org part:m#2|m|alice@example.org |part:m#2"
for folder in home/Attachments home/Docs; do
    run owner/set_collection_kind ":collection='$folder'" ":account='home'" ":kind='$file_kind'"
done
file home/Attachments 'part:m#2' 2 NULL Report.pdf "'2'"
file home/Attachments 'part:m#3' 3 NULL photo.jpg "'3'"
file work/Docs 'part:m#3' 3 "'hx'" photo.jpg "'3'"
sql "UPDATE items SET deleted = 1 WHERE collection IN ('home/Attachments', 'work/Docs') AND link_id = 'part:m#3';"
ref $mail_kind m $file_kind local related user >/dev/null
expect "file: a message's attachments are the account's, live, by the attachment role, held by a live body only" \
    "$(run read/list_attachments ":account='home'" ":link_id='m'" | cut -d'|' -f1,2 | tr '\n' ' ')|$(run read/list_attachments ":account='work'" ":link_id='m'" | cut -d'|' -f1,8 | tr '\n' ' ')" \
    "part:m#2|home/Attachments |part:m#2|hx part:m#3| "
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
    "work/Docs:hx|0"
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
    "hx||1"

# --- The local time collection holds unbound time entries (§14.3) -----------

fresh
time_id=$'\x01time'
run owner/set_collection_kind ":collection='$time_id'" ":account=NULL" ":kind='$cal_kind'"
run owner/set_collection_name ":collection='$time_id'" ":account=NULL" ":name='time'"
object he
object hj
item "$time_id" entry 1 "'he'"
run owner/upsert_event_summary ":collection='$time_id'" ":link_id='entry'" ":uid='entry'" ":summary='Paint the hallway'" \
    ":location=NULL" ":dtstart='2026-10-28T09:00:00Z'" ":dtstart_tzid=NULL" ":dtstart_value=NULL" ":dtend=NULL" \
    ":recurring=0" ":until=NULL"
item "$time_id" start 2 "'hj'"
run owner/upsert_journal_summary ":collection='$time_id'" ":link_id='start'" ":uid='start'" ":summary='Paint the hallway'" \
    ":dtstart='2026-10-28T09:00:00Z'" ":dtstart_tzid=NULL" ":dtstart_value=NULL"
expect "time: the local time collection is a calendar collection under no account, no source syncing it" \
    "$(run read/list_collections_by_account ":account=NULL" | cut -d'|' -f2,3,4 | tr -d '\001')|$(run owner/collection_sources ":collection='$time_id'")" \
    "|text/calendar|time|"
expect "time: a running entry is an event with no end, a journal entry has its instant" \
    "$(sql "SELECT ifnull(dtend, 'running') FROM event_summary WHERE link_id = 'entry';")|$(sql "SELECT dtstart FROM journal_summary WHERE link_id = 'start';")" \
    "running|2026-10-28T09:00:00Z"
expect "time: an entry no source binds is deleted with its summary and the hash to release" \
    "$(run owner/delete_unbound_item ":collection='$time_id'" ":link_id='entry'" | cut -d'|' -f1)|$(sql "SELECT count(*) FROM event_summary;")|$(run owner/delete_unbound_item ":collection='$time_id'" ":link_id='start'" | cut -d'|' -f1)|$(sql "SELECT count(*) FROM items;")" \
    "he|0|hj|0"

# --- An action on an item no source binds is the store's to settle (§15.3) --

fresh
collection Local
collection INBOX
run owner/upsert_checkpoint ":collection='INBOX'" ":source='imap'" ":checkpoint=NULL"
object hn
item Local note 1 "'hn'"
item Local gone 2 "'hn'"
item INBOX fresh 3 "'hn'"
expect "unbound: a collection no source syncs answers none, one whose source holds a checkpoint and no binding answers it, and no source binds either item" \
    "$(run owner/collection_sources ":collection='Local'")|$(run owner/collection_sources ":collection='INBOX'")|$(run read/list_item_bindings ":collection='Local'" ":link_id='note'")$(run read/list_item_bindings ":collection='INBOX'" ":link_id='fresh'")" \
    "|imap|"
before="$(sql "SELECT changed FROM items WHERE link_id = 'note';")"
run owner/update_item ":collection='Local'" ":link_id='note'" ":flags='[\"\\\\Flagged\"]'" ":object_hash='hn'" ":sort_key=''" \
    ":level=2" ":deleted=0" ":conflicted=0" ":conflict_object=NULL"
run owner/retain_item ":collection='Local'" ":link_id='gone'" ":source='owner'"
expect "unbound: a set-flags applies to the item directly and moves its stamp; a remove retains it, its body still pinned" \
    "$(sql "SELECT flags, changed > $before FROM items WHERE link_id = 'note';")|$(sql "SELECT deleted, retained_at IS NOT NULL, object_hash FROM items WHERE link_id = 'gone';")|$(run read/count_retained ":collection='Local'")" \
    "[\"\\\\Flagged\"]|1|1|1|hn|1"

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
object ht
object hn
item tasks-a t1 1 "'ht'"
bind tasks-a t1 caldav a.ics 1
sql "UPDATE items SET deleted = 1 WHERE collection = 'tasks-a' AND link_id = 't1';"
item tasks-b n1 2 "'hn'"
bind tasks-b n1 caldav $'\x01n1' 0
run owner/supersede_item ":collection='tasks-a'" ":link_id='t1'" ":by_collection='tasks-b'" ":by_link_id='n1'"
expect "supersedes: a pending superseding create holds the tombstone" \
    "$(run owner/list_superseded_pending ":collection='tasks-a'")" "t1"
expect "supersedes: nothing is held in the superseding collection" \
    "$(run owner/list_superseded_pending ":collection='tasks-b'")" ""
sql "UPDATE bindings SET handle = 'n1.ics', base_flags = '[]', base_present = 1 WHERE collection = 'tasks-b';"
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
    "$(sql "SELECT by_collection FROM supersessions;")|$(run owner/list_superseded_pending ":collection='tasks-a'")" "tasks-c|t1"
sql "DELETE FROM items WHERE collection = 'tasks-c';"
expect "supersedes: the superseding row gone takes the pair" "$(sql "SELECT count(*) FROM supersessions;")" "0"

# --- A superseding create of the same identity names what to move (§15.3) --

fresh
run owner/set_collection_kind ":collection='tasks-a'" ":account=NULL" ":kind='$cal_kind'"
run owner/set_collection_kind ":collection='tasks-b'" ":account=NULL" ":kind='$cal_kind'"
object ht
object hn
item tasks-a t1 1 "'ht'"
bind tasks-a t1 caldav a.ics 1
sql "UPDATE bindings SET base_revision = 'r1' WHERE collection = 'tasks-a';"
sql "UPDATE items SET deleted = 1 WHERE collection = 'tasks-a' AND link_id = 't1';"
item tasks-b t1 2 "'hn'"
bind tasks-b t1 caldav $'\x01t1' 0
run owner/supersede_item ":collection='tasks-a'" ":link_id='t1'" ":by_collection='tasks-b'" ":by_link_id='t1'"
expect "supersedes: a create keeping the identity names the binding it may be moved from" \
    "$(run owner/list_superseded_bindings ":collection='tasks-b'" ":source='caldav'")" "t1|tasks-a|a.ics|r1"
expect "supersedes: another source binds nothing to move" \
    "$(run owner/list_superseded_bindings ":collection='tasks-b'" ":source='other'")" ""
expect "supersedes: the superseded collection has nothing to move in" \
    "$(run owner/list_superseded_bindings ":collection='tasks-a'" ":source='caldav'")" ""
item tasks-b n1 3 "'hn'"
item tasks-a t2 4 "'ht'"
bind tasks-a t2 caldav b.ics 1
sql "UPDATE items SET deleted = 1 WHERE collection = 'tasks-a' AND link_id = 't2';"
run owner/supersede_item ":collection='tasks-a'" ":link_id='t2'" ":by_collection='tasks-b'" ":by_link_id='n1'"
expect "supersedes: a create of another identity is a plain create" \
    "$(run owner/list_superseded_bindings ":collection='tasks-b'" ":source='caldav'")" "t1|tasks-a|a.ics|r1"
sql "UPDATE items SET deleted = 0 WHERE collection = 'tasks-a' AND link_id = 't1';"
expect "supersedes: a revived item is no member to move" \
    "$(run owner/list_superseded_bindings ":collection='tasks-b'" ":source='caldav'")" ""
sql "UPDATE items SET deleted = 1 WHERE collection = 'tasks-a' AND link_id = 't1';"
sql "UPDATE bindings SET handle = 'a.ics', base_flags = '[]', base_present = 1 WHERE collection = 'tasks-b' AND link_id = 't1';"
expect "supersedes: the create accepted has nothing left to move" \
    "$(run owner/list_superseded_bindings ":collection='tasks-b'" ":source='caldav'")" ""

fresh
run owner/set_collection_kind ":collection='tasks-a'" ":account=NULL" ":kind='$cal_kind'"
run owner/set_collection_kind ":collection='tasks-b'" ":account=NULL" ":kind='$cal_kind'"
run queue/enqueue_action ":producer='p'" ":collection='tasks-b'" ":action='add'" \
    ":payload='{\"v\":1,\"flags\":[],\"supersedes\":{\"collection\":\"tasks-a\",\"seq\":1}}'" ":object_hash=NULL"
run queue/enqueue_action ":producer='p'" ":collection='tasks-b'" ":action='add'" ":payload='{\"v\":1,\"flags\":[]}'" ":object_hash=NULL"
run owner/rename_queue_targets ":collection='tasks-a'" ":new_id='tasks-2026'"
run owner/rename_collection ":collection='tasks-a'" ":new_id='tasks-2026'"
expect "supersedes: a rename follows into a pending add's supersedes, and leaves a plain add alone" \
    "$(sql "SELECT ifnull(json_extract(payload, '\$.supersedes.collection'), '-') FROM queue ORDER BY id;" | tr '\n' ' ')" "tasks-2026 - "

# --- A task's source mail answered is a reply another mail names (§14.1) ----

fresh
collection INBOX
collection Sent
run owner/set_collection_role ":collection='Sent'" ":role='sent'"
mail INBOX r1 1 10 NULL
sql "UPDATE mail_summary SET in_reply_to = '[\"other@x\",\"asked@x\"]' WHERE link_id = 'r1';"
mail Sent r2 2 11 NULL
sql "UPDATE mail_summary SET in_reply_to = '[\"mine@x\"]' WHERE link_id = 'r2';"
mail INBOX r3 3 12 NULL
sql "UPDATE mail_summary SET in_reply_to = '[\"gone@x\"]' WHERE link_id = 'r3'; UPDATE items SET deleted = 1 WHERE link_id = 'r3';"
mail INBOX r4 4 13 NULL
sql "UPDATE mail_summary SET in_reply_to = '[\"asked@x\"]' WHERE link_id = 'r4';"
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
     INSERT INTO item_address(collection, link_id, role, position, address) VALUES('Cards', 'bob', 'email', 0, 'bob@plan.example');"
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

# --- A store is reconciled against the canonical schema's own text (§6) -----

fresh
rm -f "$dir/scratch.db"
for migration in "$root"/migrations/storage/*.sql; do
    sqlite3 "$dir/scratch.db" < "$migration"
done
# shape <db>: every table, index and trigger with its text, comments dropped
# and whitespace collapsed, one per line.
shape() {
    sqlite3 -separator ' ' "$1" "SELECT type, name, replace(sql, char(10), ' #NL# ')
                  FROM sqlite_schema WHERE sql IS NOT NULL ORDER BY type, name;" |
        awk '{ t = $1; nm = $2; $1 = ""; $2 = ""; n = split($0, lines, "#NL#"); s = "";
                        for (i = 1; i <= n; i++) { l = lines[i]; sub(/--.*/, "", l); s = s " " l }
                        gsub(/[ \t]+/, " ", s); sub(/^ /, "", s); sub(/ $/, "", s); print t " " nm " " s }'
}
differs() {
    diff <(shape "$dir/pimdir.db") <(shape "$dir/scratch.db") | grep '^[<>]' | cut -d' ' -f3 | sort -u | tr '\n' ' '
}
# rebuild <table>: §6's rebuild of one table from the canonical text.
rebuild() {
    local t="$1" drops creates cols
    drops="$(sql "SELECT 'DROP ' || upper(type) || ' ' || name || ';' FROM sqlite_schema WHERE tbl_name = '$t' AND type IN ('index', 'trigger') AND sql IS NOT NULL;")"
    creates="$(sqlite3 "$dir/scratch.db" "SELECT sql || ';' FROM sqlite_schema WHERE tbl_name = '$t' AND type IN ('index', 'trigger') AND sql IS NOT NULL;")"
    cols="$(sql "SELECT group_concat(name, ', ') FROM pragma_table_info('$t') WHERE name IN ($(sqlite3 "$dir/scratch.db" "SELECT group_concat(quote(name)) FROM pragma_table_info('$t');"));")"
    sqlite3 "$dir/pimdir.db" "PRAGMA foreign_keys = OFF; PRAGMA legacy_alter_table = ON; BEGIN; $drops
        ALTER TABLE $t RENAME TO ${t}_aside;
        $(sqlite3 "$dir/scratch.db" "SELECT sql FROM sqlite_schema WHERE name = '$t';");
        INSERT INTO $t ($cols) SELECT $cols FROM ${t}_aside;
        UPDATE sqlite_sequence SET seq = max(seq, (SELECT seq FROM sqlite_sequence WHERE name = '${t}_aside')) WHERE name = '$t';
        INSERT INTO sqlite_sequence(name, seq) SELECT '$t', seq FROM sqlite_sequence
            WHERE name = '${t}_aside' AND NOT EXISTS (SELECT 1 FROM sqlite_sequence WHERE name = '$t');
        DROP TABLE ${t}_aside; $creates COMMIT;"
}
expect "reconcile: a store the canonical migrations created is current" "$(differs)" ""
collection INBOX
run queue/enqueue_action ":producer='p'" ":collection='INBOX'" ":action='remove'" ":payload='{\"v\":1}'" ":object_hash=NULL" >/dev/null
run queue/enqueue_action ":producer='p'" ":collection='INBOX'" ":action='remove'" ":payload='{\"v\":1}'" ":object_hash=NULL" >/dev/null
sql "DELETE FROM queue WHERE id = 2;"
# An earlier draft's shape: no derivation, a closed role, an open kind, a
# ladder taking 0, edited comments, a shared body pinned by nothing.
sql "ALTER TABLE store_meta DROP COLUMN derivation;"
printf '.dbconfig defensive off\n%s\n' "PRAGMA writable_schema = ON;
    UPDATE sqlite_schema SET sql = replace(sql, 'role        TEXT,', 'role        TEXT CHECK (role IS NULL OR role IN (''inbox'', ''sent'')),') WHERE name = 'collections';
    UPDATE sqlite_schema SET sql = replace(sql, ' CHECK (kind IN ('''', ''message/rfc822'', ''text/vcard'', ''text/calendar'',' || char(10) || '                ''application/octet-stream''))', '') WHERE name = 'collections';
    UPDATE sqlite_schema SET sql = replace(sql, 'CHECK (level IN (1, 2))', 'CHECK (level IN (0, 1, 2))') WHERE name = 'items';
    UPDATE sqlite_schema SET sql = replace(sql, '-- global append order', '-- an edited comment') WHERE name = 'queue';
    UPDATE sqlite_schema SET sql = replace(sql, 'shared_object     TEXT REFERENCES objects(hash),', 'shared_object     TEXT,') WHERE name = 'bindings';
    UPDATE sqlite_schema SET sql = replace(sql, 'AUTOINCREMENT,', 'AUTOINCREMENT, -- a comment of an earlier owner') WHERE name = 'queue';" | sqlite3 "$dir/pimdir.db" >/dev/null
sql "INSERT INTO collections(id, kind, name) VALUES('Lists', 'text/x-vlist', 'Lists');
     INSERT INTO items(collection, link_id, seq, flags, level) VALUES('INBOX', 'old', 9, '[]', 0);
     DROP INDEX bindings_by_shared_object;
     INSERT INTO bindings(collection, link_id, source, handle, base_present, shared_object) VALUES('INBOX', 'old', 'imap', '9', 1, 'swept');"
# What another implementation kept in the store: a table and a column of its
# own, which pimdir.db does not hold (§6).
sql "CREATE TABLE x_notes (id INTEGER PRIMARY KEY, note TEXT) STRICT;
     INSERT INTO x_notes(note) VALUES('mine');
     ALTER TABLE queue ADD COLUMN x_note TEXT;"
expect "reconcile: a table whose constraint or column moved differs, a comment does not, nor does a table or column of another's" "$(differs)" "bindings bindings_by_shared_object collections items queue store_meta x_notes "
expect "reconcile: the closed ladder refuses an earlier draft's 0 until it is repaired" \
    "$(rebuild items 2>&1 | grep -c CHECK)|$(sql "SELECT level FROM items WHERE link_id = 'old';")" "1|0"
run owner/recompute_refcounts
run owner/repair_levels
run owner/repair_kinds
rebuild collections
rebuild items
rebuild bindings
expect "reconcile: a shared body an earlier draft let the collector sweep dangles under the new key until it is repaired" \
    "$(sql "PRAGMA foreign_key_check;" | cut -d'|' -f1)|$(run owner/repair_shared_objects)$(sql "PRAGMA foreign_key_check;")|$(sql "SELECT shared_object IS NULL FROM bindings WHERE link_id = 'old';")" "bindings||1"
rebuild queue
rebuild store_meta
# Step 3: drop every table the canonical schema lacks.
for extra in $(sql "SELECT name FROM sqlite_schema WHERE type = 'table' AND name NOT LIKE 'sqlite_%';"); do
    if [ -z "$(sqlite3 "$dir/scratch.db" "SELECT name FROM sqlite_schema WHERE type = 'table' AND name = '$extra';")" ]; then
        sql "DROP TABLE $extra;"
    fi
done
expect "reconcile: a table and a column the canonical schema lacks do not survive an owner's open" \
    "$(sql "SELECT count(*) FROM sqlite_schema WHERE name = 'x_notes';")|$(sql "SELECT count(*) FROM pragma_table_info('queue') WHERE name = 'x_note';")|$(sql "SELECT count(*) FROM queue;")" "0|0|1"
expect "reconcile: rebuilt from the canonical text, nothing differs and no key dangles" \
    "$(differs)|$(sql "PRAGMA foreign_key_check;")|$(sql "SELECT count(*) FROM collections;")" "||2"
expect "reconcile: a 0 is repaired to Meta, a kind outside the set to undeclared, the revision added at 1" \
    "$(sql "SELECT level FROM items WHERE link_id = 'old';")|$(sql "SELECT kind FROM collections WHERE id = 'Lists';")|$(run read/load_store_meta | cut -d'|' -f2,8)" "1||1|1"
expect "reconcile: the rebuilt tables take the new constraints, their triggers back" \
    "$(run owner/set_collection_kind ":collection='Files'" ":account=NULL" ":kind='application/octet-stream'")$(run owner/set_collection_role ":collection='Files'" ":role='attachments'")$(run owner/set_collection_role ":collection='INBOX'" ":role='snoozed'")$(sql "SELECT group_concat(role, ' ') FROM (SELECT role FROM collections WHERE role IS NOT NULL ORDER BY id);")|$(fails owner/set_collection_kind ":collection='Lists'" ":account=NULL" ":kind='text/x-vlist'" && echo refused)|$(sql "UPDATE items SET level = 0 WHERE link_id = 'old';" 2>&1 | grep -c CHECK)|$(sql "SELECT count(*) FROM sqlite_schema WHERE tbl_name = 'collections' AND type = 'trigger';")" \
    "attachments snoozed|refused|1|$(sqlite3 "$dir/scratch.db" "SELECT count(*) FROM sqlite_schema WHERE tbl_name = 'collections' AND type = 'trigger';")"
expect "reconcile: an AUTOINCREMENT counter carries over, no id reused" \
    "$(run queue/enqueue_action ":producer='p'" ":collection='INBOX'" ":action='remove'" ":payload='{\"v\":1}'" ":object_hash=NULL")$(sql "SELECT max(id) FROM queue;")" "3"
object hb
mail INBOX held 10 20 "'2026-10-06T08:00:00Z'"
mail INBOX bare 11 21 "'2026-10-06T08:00:00Z'"
sql "UPDATE items SET object_hash = 'hb' WHERE link_id = 'held';"
expect "reconcile: list_held_mail pages the rows holding a body" \
    "$(run owner/list_held_mail ":after_collection=NULL" ":after_link_id=NULL" ":limit=10" | cut -d'|' -f2,4)|$(run owner/list_held_mail ":after_collection='INBOX'" ":after_link_id='held'" ":limit=10")" "held|hb|"
run owner/set_collection_kind ":collection='Cal'" ":account=NULL" ":kind='$cal_kind'"
item Cal tk 12 "'hb'"
item Cal tn 13
item Cal ev 14 "'hb'"
sql "INSERT INTO task_summary (collection, link_id, summary) VALUES ('Cal', 'tk', 't'), ('Cal', 'tn', 't');"
expect "reconcile: list_held_tasks pages the task rows holding a body, no event, no task without one" \
    "$(run owner/list_held_tasks ":after_collection=NULL" ":after_link_id=NULL" ":limit=10" | cut -d'|' -f2,4)|$(run owner/list_held_tasks ":after_collection='Cal'" ":after_link_id='tk'" ":limit=10")" "tk|hb|"
run owner/backfill_invitation ":collection='INBOX'" ":link_id='held'" ":invitation='ev'"
run owner/backfill_invitation ":collection='INBOX'" ":link_id='held'" ":invitation=NULL"
run owner/backfill_task_organisation ":collection='Cal'" ":link_id='tk'" ":priority=1" ":categories='[\"inbox\"]'" ":parent='proj'" ":mid='m1'"
expect "reconcile: the backfills write what the body gives, a known invitation never cleared" \
    "$(sql "SELECT invitation FROM mail_summary WHERE link_id = 'held';")|$(sql "SELECT priority, categories, parent, mid FROM task_summary WHERE link_id = 'tk';")" "ev|1|[\"inbox\"]|proj|m1"

# --- A reader reads an older store as its reconciliation would (§6) ---------

# reader <profile/name> <sed -E substitution> [:param=literal...]: a canonical
# statement as a reader runs it on a store lacking a column, every mention of
# the column replaced by the value it reads as.
reader() {
    local file="$1" subst="$2"; shift 2
    {
        echo "PRAGMA foreign_keys = ON;"
        for binding in "$@"; do
            echo ".parameter set ${binding%%=*} ${binding#*=}"
        done
        sed -E "$subst" "$root/queries/storage/$file.sql"
    } | sqlite3 "$dir/pimdir.db"
}

fresh
collection INBOX
# An earlier draft's shape: sources with no coverage, store_meta with no
# derivation revision.
sql "DROP TABLE sources;
     CREATE TABLE sources (collection TEXT NOT NULL, source TEXT NOT NULL, checkpoint BLOB,
         round INTEGER NOT NULL DEFAULT 0, round_since TEXT, round_until TEXT, round_cursor BLOB,
         round_checkpoint BLOB, round_started_at TEXT, round_band INTEGER NOT NULL DEFAULT 0,
         PRIMARY KEY (collection, source)) STRICT;
     INSERT INTO sources(collection, source) VALUES('INBOX', 'imap');
     ALTER TABLE store_meta DROP COLUMN derivation;"
expect "reader: a canonical statement naming a column an older store lacks fails as written" \
    "$(fails read/list_coverage ":collection='INBOX'" && echo refused)|$(fails read/load_store_meta && echo refused)" "refused|refused"
expect "reader: a nullable column reads NULL, so the source answers with a coverage never closed; a NOT NULL one its default" \
    "$(reader read/list_coverage 's/\b(covered_since|covered_until|covered_at)\b/NULL/g' ":collection='INBOX'")|$(reader read/load_store_meta 's/\bderivation\b/1/g' | cut -d'|' -f8)" \
    "imap|||||||1"

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
expect "sum: a message filed in two collections counts once, at its largest size" \
    "$(run read/sum_mail "$both" ":seen=NULL" ":attachment=NULL" ":since=NULL" ":until=NULL")" "4|150|2"
object hc
sql "UPDATE items SET object_hash = 'hc', level = 2 WHERE collection = 'INBOX' AND link_id = 'c';"
expect "sum: held 1 is what a release frees, held 0 what a download fetches" \
    "$(run read/sum_mail "$both" ":seen=NULL" ":attachment=NULL" ":held=1" ":since=NULL" ":until=NULL")|$(run read/sum_mail "$both" ":seen=NULL" ":attachment=NULL" ":held=0" ":since=NULL" ":until=NULL")" \
    "1|50|0|3|100|2"
sql "UPDATE items SET object_hash = 'hc', level = 2 WHERE collection = 'Sent' AND link_id = 'a';"
expect "sum: a body one placement holds holds the message" \
    "$(run read/sum_mail "$inbox" ":seen=NULL" ":attachment=NULL" ":held=0" ":since=NULL" ":until=NULL")|$(run read/sum_mail "$both" ":seen=NULL" ":attachment=NULL" ":held=0" ":since=NULL" ":until=NULL")" \
    "3|100|2|2|0|2"
expect "row: one mail row by key, in the page's shape" \
    "$(run read/get_mail_row ":collection='INBOX'" ":link_id='c'" | cut -d'|' -f1,2,3,5,10)" "INBOX|3|c|hc|Invoice 100%"

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

# --- The search index (SEARCH.md) --------------------------------------------

# index: an empty index.db at the canonical search schema.
index() {
    for migration in "$root"/migrations/search/*.sql; do
        sqlite3 "$dir/index.db" "BEGIN; $(cat "$migration") PRAGMA user_version = 1; COMMIT;"
    done
}

# isearch <name> [:param=literal...]: one statement of queries/search, bound,
# on index.db with the store attached as `store` (SEARCH.md §3).
isearch() {
    local file="$1"; shift
    {
        echo "PRAGMA foreign_keys = ON;"
        echo "ATTACH '$dir/pimdir.db' AS store;"
        for binding in "$@"; do
            echo ".parameter set ${binding%%=*} ${binding#*=}"
        done
        cat "$root/queries/search/$file.sql"
    } | sqlite3 "$dir/index.db"
}

fresh
index
object_id="$(isearch insert_object ":hash='h1'" ":status='ok'" ":attachment=0")"
isearch insert_chunk ":object=$object_id" ":ord=1" ":field='note'" ":start=0" ":end=4"
isearch insert_chunk ":object=$object_id" ":ord=0" ":field='body'" ":start=0" ":end=10"
expect "chunk: a body's chunks list in text order across fields" \
    "$(isearch chunks_of ":hash='h1'" | tr '\n' ' ')" "0|body|0|10 1|note|0|4 "
isearch delete_object ":rowid=$object_id"
isearch delete_object_row ":hash='h1'"
expect "chunk: the chunks go with their object" \
    "$(sqlite3 "$dir/index.db" "SELECT count(*) FROM chunk;")" "0"

fresh
index
run owner/set_collection_kind ":collection='Cal'" ":account=NULL" ":kind='text/calendar'"
item Cal ev 1
sql "UPDATE items SET sort_key = '2026-09-01T10:00:00Z' WHERE link_id = 'ev';"
run owner/upsert_event_summary ":collection='Cal'" ":link_id='ev'" ":uid='ev'" ":summary='Review'" ":location=NULL" \
    ":dtstart='20260901T120000'" ":dtstart_tzid='Europe/Paris'" ":dtstart_value=NULL" ":dtend=NULL" ":recurring=0" ":until=NULL"
isearch init_index_meta ":version=1" ":tokenizer='unicode61 remove_diacritics 2'"
isearch set_horizon ":horizon_start='2025-08-20T12:00:00Z'" ":horizon_end='2028-08-20T12:00:00Z'"
isearch set_tzdb_version ":tzdb_version='2026a'"
window=(":old_start='2025-08-20T12:00:00Z'" ":old_end='2028-08-20T12:00:00Z'"
        ":new_start='2025-08-20T12:00:00Z'" ":new_end='2028-08-20T12:00:00Z'")
expect "tzdb: the version the occurrences stand under re-expands nothing" \
    "$(isearch items_to_reexpand "${window[@]}" ":tzdb_version='2026a'")" ""
expect "tzdb: another version re-expands a single zoned event inside the horizon" \
    "$(isearch items_to_reexpand "${window[@]}" ":tzdb_version='2026b'")" "Cal|1"


run owner/set_collection_kind ":collection='Docs'" ":account=NULL" ":kind='application/octet-stream'"
item Docs plan 2
expect "coverage: a bodiless file hides nothing from search and is never counted" \
    "$(isearch coverage)" "text/calendar|1"

# --- A zero-length occurrence falls in the range it starts (SEARCH.md §8.1) --

isearch upsert_placement ":collection='Cal'" ":seq=1" ":link_id='ev'" ":hash=NULL" > /dev/null
isearch insert_occurrence ":collection='Cal'" ":seq=1" ":start='2026-09-01T00:00:00Z'" ":end='2026-09-01T00:00:00Z'"
day=(":start='2026-09-01T00:00:00Z'" ":end='2026-09-02T00:00:00Z'")
expect "occurrence: a zero-length one at the start of a range is in it, one at its end is not" \
    "$(isearch occurring_between "${day[@]}")|$(isearch occurring_between ":start='2026-08-31T00:00:00Z'" ":end='2026-09-01T00:00:00Z'")" "Cal|1|"

expect "feed: a batch reads each row's stamp, the cursor it may record" \
    "$(isearch load_changed_items ":since=0" ":limit=10" | cut -d'|' -f2,10 | tr '\n' ' ')" \
    "$(sql "SELECT link_id || '|' || changed FROM items ORDER BY changed;" | tr '\n' ' ')"

# --- A calendar item's attachment field is read by a seek (SEARCH.md §6, §8) -

fresh
index
isearch insert_object ":hash='ha'" ":status='ok'" ":attachment=1" > /dev/null
isearch insert_object ":hash='hn'" ":status='ok'" ":attachment=0" > /dev/null
isearch upsert_placement ":collection='Cal'" ":seq=1" ":link_id='attach'" ":hash='ha'" > /dev/null
isearch upsert_placement ":collection='Cal'" ":seq=2" ":link_id='plain'" ":hash='hn'" > /dev/null
isearch upsert_placement ":collection='Cal'" ":seq=3" ":link_id='bare'" ":hash=NULL" > /dev/null
expect "attached: a body whose attachment field holds text answers, an empty field and no body do not" \
    "$(isearch attached | tr '\n' ' ')|$(sqlite3 "$dir/index.db" "INSERT INTO object(hash, status) VALUES('hx', 'ok');" 2>&1 | grep -c 'NOT NULL')" "Cal|1 |1"

# --- A rename a cut pass folded past is still reconciled (SEARCH.md §4, §8.2) -

fresh
index
collection INBOX
item INBOX a 1
isearch init_index_meta ":version=1" ":tokenizer='unicode61 remove_diacritics 2'"
head="$(run read/load_change_cursor | cut -d'|' -f1)"
isearch set_index_cursor ":store_change=$head" ":store_purges=0" ":store_reconciled=$head"
expect "behind: an index a pass completed over every stamp is not behind" "$(isearch behind)" "0"
run owner/rename_collection ":collection='INBOX'" ":new_id='Archive'"
moved="$(run read/load_change_cursor | cut -d'|' -f1)"
expect "behind: a rename draws the stamps the index has yet to fold" "$(isearch behind)" "$((moved - head))"
# A batch folds the restamped item, records its stamp, and the deadline cuts
# the pass before it completes.
isearch set_index_cursor ":store_change=$moved" ":store_purges=0" ":store_reconciled=$head"
reconciled="$(isearch load_index_meta | cut -d'|' -f8)"
change="$(isearch load_index_meta | cut -d'|' -f3)"
expect "reconciled: past a batch, the collection's stamp lies above store_reconciled and not above store_change" \
    "$(run read/list_collections_changed_since ":since=$reconciled" ":limit=10" | cut -d'|' -f1)|$(run read/list_collections_changed_since ":since=$change" ":limit=10")|$(isearch behind)" \
    "Archive||0"

if [ "$failures" -gt 0 ]; then
    echo "$failures invariant(s) broken" >&2
    exit 1
fi

echo "every invariant scenario holds"
