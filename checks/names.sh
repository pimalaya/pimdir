#!/usr/bin/env bash
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Keeps the documents and queries/ naming the same statements: every statement
# file is named in a document, every snake_case identifier a document writes
# in backticks is a statement, a table, a column, a pragma or a vector field,
# and a statement written with its arguments names its parameters. SEARCH.md
# names each search statement with its profile, STORAGE.md Annex B every
# capability, and each part its profiles and the vectors they owe; an
# informative document writes no key word; the format version a new store or
# index records is its part's own, and README's Status names each part's; a
# backticked word of one part is a schema name, a statement, a vector field or
# a word of the list below; the tokenizer the index and the scenarios state is
# SEARCH.md's. One key word marks one level: no part writes SHALL outside the
# sentence naming the key words. A reader's and a producer's statements are
# each named in a section its profile's row of STORAGE.md §17 lists, and the
# paragraphs the guide's reading paths quote are STORAGE.md's. A version of a
# vector format a document states is the one its schema holds. No statement
# the load, the write or the sync part names reads an item's properties. Needs
# sqlite3 alone, to read the tables and columns off the schemas.
set -euo pipefail

root="${1:-$PWD}"
dir="$(mktemp -d)"
trap 'rm -rf "$dir"' EXIT
documents=(OVERVIEW.md STORAGE.md SYNC.md SEARCH.md GUIDE.md conventions/gtd.md README.md vectors/README.md)
failures=0

for part in storage search; do
    for migration in "$root"/migrations/$part/*.sql; do
        sqlite3 "$dir/$part.db" < "$migration"
    done
done

statements="$(find "$root/queries" -name '*.sql' -exec basename {} .sql \; | sort -u)"

known="$(
    for part in storage search; do
        sqlite3 "$dir/$part.db" "SELECT name FROM sqlite_schema WHERE name NOT LIKE 'sqlite_%';
            SELECT p.name FROM sqlite_schema s, pragma_table_info(s.name) p WHERE s.type IN ('table', 'view');"
    done
    # Pragmas, SQLite features, vector fields, result columns, JSON keys and
    # platform calls (STORAGE.md §5) the documents write.
    printf '%s\n' user_version data_version foreign_keys journal_mode locking_mode integrity_check \
        table_list contentless_delete json_each json_valid writable_schema sqlite_sequence \
        sqlite_schema sqlite_master core_autocrlf recurrence_id base32 body_hex body_len input_hex input_utf8 digest_hex \
        name_chars digest_bytes if_match set_flags no_uid_conflict collect_garbage \
        meta_attachment round_open cursor_rejected interrupted_after scope_bound horizon_left \
        accept_absences base_flags in_reply_to renamex_np object_hash
    # The members the vector formats and the payloads define.
    grep -oh '"[a-z][a-z0-9_]*":' "$root"/vectors/schema/*.json "$root"/payloads/*.json \
        "$root"/conventions/gtd/writers.schema.json | tr -d '":'
)"

# A backticked identifier, the name alone: a call's parameters are dropped and
# a `<kind>` pattern stands for the five summary kinds.
mentioned="$(
    grep -oh '`[a-z][a-z0-9]*\(_[a-z0-9<>]\+\)\+[(`]' "${documents[@]/#/$root/}" | tr -d '`(' | sort -u |
    while read -r name; do
        case "$name" in
            *'<kind>'*) for kind in mail contact event task journal file; do echo "${name//<kind>/$kind}"; done ;;
            *) echo "$name" ;;
        esac
    done | sort -u
)"

# The format version init_store_meta writes is STORAGE.md's own (§4.2), so a
# store names the draft that created it and no other.
# released <version>: the name a store or an index records for a part's
# version (§4.2): a draft's own name, and for a release `<part>-vN`, its major
# alone, so storage-v1.0.0 and storage-v1.2.0 both write storage-v1.
released() {
    sed 's/^\([a-z]*-v[0-9][0-9]*\)\.[0-9][0-9]*\.[0-9][0-9]*$/\1/' <<< "$1"
}

status="$(sed -n 's/^Status: \(storage-[a-z0-9.-]*\),.*/\1/p' "$root/STORAGE.md")"
marker="$(grep -o "'storage-[a-z0-9-]*'" "$root/queries/storage/owner/init_store_meta.sql" | tr -d "'" || true)"
if ! grep -qxE 'storage-(draft-[0-9]+|v[0-9]+\.[0-9]+\.[0-9]+)' <<< "$status"; then
    echo "STORAGE.md's Status line names [$status], neither a draft nor a release" >&2
    failures=$((failures + 1))
fi
if [ -z "$status" ] || [ "$marker" != "$(released "$status")" ]; then
    echo "init_store_meta writes [$marker] as the format version, STORAGE.md is [$status]" >&2
    failures=$((failures + 1))
fi

# The format version init_index_meta writes is SEARCH.md's own (§2), so an
# index names the draft that built it and an indexer of another draft rebuilds
# or refuses it rather than reading it as its own.
search_status="$(sed -n 's/^Status: \(search-[a-z0-9.-]*\),.*/\1/p' "$root/SEARCH.md")"
search_marker="$(grep -o "'search-[a-z0-9-]*'" "$root/queries/search/init_index_meta.sql" | tr -d "'" || true)"
if [ -z "$search_status" ] || [ "$search_marker" != "$(released "$search_status")" ]; then
    echo "init_index_meta writes [$search_marker] as the format version, SEARCH.md is [$search_status]" >&2
    failures=$((failures + 1))
fi

# README's Status names the version each part's own Status line states, so
# the front page never advertises a draft the documents moved past.
for part in STORAGE.md SYNC.md SEARCH.md; do
    version="$(sed -n 's/^Status: \([a-z]*-[a-z0-9.-]*\),.*/\1/p' "$root/$part")"
    if [ -z "$version" ] || ! sed -n '/^## Status$/,/^## /p' "$root/README.md" | grep -q "\*\*$version\*\*"; then
        echo "README.md's Status does not name $part's version [$version]" >&2
        failures=$((failures + 1))
    fi
done
if [ "$(sed -n '/^## Status$/,/^## /p' "$root/README.md" | grep -o '\*\*[a-z]*-\(draft-[0-9]*\|v[0-9.]*\)\*\*' | wc -l)" != 3 ]; then
    echo "README.md's Status names another number of part versions than the three parts" >&2
    failures=$((failures + 1))
fi

# A document names a part's version as the one its Status line states, as
# the first release, which the drafts name before it exists, or as one of the
# past versions listed here for the fact they record (the first draft whose
# store names its draft, the first whose index does). So a draft's name left
# in the prose after a bump, or after the release, fails, and the commit that
# moves a Status line moves every sentence naming the version with it.
past="storage-draft-08 search-draft-08"
versioned=("${documents[@]}")
[ ! -f "$root/AGENTS.md" ] || versioned+=(AGENTS.md)
while read -r name; do
    [ -n "$name" ] || continue
    part="${name%%-*}"
    case "$part" in
        storage) current="$status" ;;
        search) current="$search_status" ;;
        sync) current="$(sed -n 's/^Status: \(sync-[a-z0-9.-]*\),.*/\1/p' "$root/SYNC.md")" ;;
        gtd) current="$(sed -n 's/^Status: \(gtd-[a-z0-9.-]*\),.*/\1/p' "$root/conventions/gtd.md")" ;;
    esac
    if [ "$name" != "$current" ] && [ "$name" != "$part-v1.0.0" ] && ! grep -qw -- "$name" <<< "$past"; then
        echo "$name: named in $(grep -lF -- "$name" "${versioned[@]/#/$root/}" | sed "s|^$root/||" | paste -sd' '), neither $part's version [$current] nor a past one this check lists" >&2
        failures=$((failures + 1))
    fi
done < <(grep -ohE '\b(storage|sync|search|gtd)-(draft-[0-9]+|v[0-9]+\.[0-9]+\.[0-9]+)\b' "${versioned[@]/#/$root/}" | sort -u)

# The tokenizer SEARCH.md §5 states is the one every full-text table of the
# canonical index declares, with its prefix indexes, and the one the scenarios
# record in index_meta, so the index, its record and the hit sets the vectors
# pin agree.
tokenizer="$(sed -n 's/^The canonical tokenizer is `\([^`]*\)`, .*`prefix = \(.[0-9 ]*.\)`.*/\1|\2/p' "$root/SEARCH.md")"
declared="$(grep -oh "tokenize = '[^']*', prefix = '[^']*'" "$root"/migrations/search/*.sql | sed "s/tokenize = '\([^']*\)', prefix = \(.*\)/\1|\2/" | sort -u)"
recorded="$(grep -oh ":tokenizer='[^']*'" "$root/checks/invariants.sh" | cut -d"'" -f2 | sort -u)"
if [ -z "$tokenizer" ] || [ "$declared" != "$tokenizer" ] || [ "$recorded" != "${tokenizer%%|*}" ]; then
    echo "SEARCH.md §5 states the tokenizer [$tokenizer]; the index declares [$declared], the scenarios record [$recorded]" >&2
    failures=$((failures + 1))
fi

# SEARCH.md §3 names every statement under queries/search/ with the profile
# that runs it, and no other, as STORAGE.md sorts its own into directories by
# profile (§4.4): a statement named only in the guide binds nobody.
table="$(sed -n '/^| Statement | Profile | § |$/,/^$/p' "$root/SEARCH.md" | tail -n +3)"
named="$(cut -d'|' -f2 <<< "$table" | tr -d ' `' | sort)"
files="$(find "$root/queries/search" -name '*.sql' -exec basename {} .sql \; | sort)"
if [ -z "$table" ] || [ "$named" != "$files" ]; then
    echo "SEARCH.md §3's statements and queries/search/ differ:" >&2
    diff <(echo "$named") <(echo "$files") >&2 || true
    failures=$((failures + 1))
fi
if cut -d'|' -f3 <<< "$table" | tr -d ' ' | grep -vxE 'indexer|queryclient|both' >&2; then
    echo "SEARCH.md §3 names a profile that is not indexer, query client or both" >&2
    failures=$((failures + 1))
fi

# The three parts state one convention (each part's opening): every statement
# of behaviour binds, a key word marking its level, and notes, examples and
# rationale are marked. A note carries no key word, adding no requirement.
convention='as shown here. Every statement of behaviour in this part is normative: a key word marks its requirement level, and a statement carrying none binds as one carrying MUST. Notes, examples and rationale are informative and marked as such: a paragraph opening with *Note:*, an instance of what a sentence states given in parentheses or after "for example", and a reason given with "so", "since" or "because", none of which adds a requirement.'
for part in STORAGE.md SYNC.md SEARCH.md; do
    line="$(grep '^The key words "MUST"' "$root/$part" || true)"
    if [[ "$line" != *"$convention"* ]]; then
        echo "$part: its conventions paragraph is not the one the three parts share" >&2
        failures=$((failures + 1))
    fi
    if grep -n '^\*Note:\*' "$root/$part" | grep -E '\b(MUST|SHALL|SHOULD|REQUIRED|RECOMMENDED|MAY|OPTIONAL)\b' >&2; then
        echo "$part: a note above carries a key word" >&2
        failures=$((failures + 1))
    fi
    # One level, one word: MUST and MUST NOT, never SHALL and SHALL NOT, which
    # BCP 14 makes their synonyms and a reader takes for another level. The
    # sentence naming the key words is the one place the word stands.
    if grep -n '\bSHALL\b' "$root/$part" | grep -v '^[0-9]*:The key words "MUST"' >&2; then
        echo "$part: a line above writes SHALL where the parts write MUST" >&2
        failures=$((failures + 1))
    fi
done

# A statement written with its arguments, `name(a, b)`, or a run of names
# before one `(a, b)`, names its parameters (`:a`) and list slots (§4.4) in
# any order, each once and no other, so a document never shows a signature the
# statement does not take.
signatures="$(
    for document in "${documents[@]}"; do
        awk -v document="$document" '{
            line = $0; n = 0
            while (match(line, /`[^`]+`/)) {
                n++
                span[n] = substr(line, RSTART + 1, RLENGTH - 2)
                gap[n] = substr(line, 1, RSTART - 1)
                line = substr(line, RSTART + RLENGTH)
            }
            for (i = 1; i <= n; i++) {
                if (span[i] ~ /^[a-z][a-z0-9_]*\(.*\)$/) {
                    open = index(span[i], "(")
                    print document ":" NR "\t" substr(span[i], 1, open - 1) "\t" substr(span[i], open + 1, length(span[i]) - open - 1)
                } else if (span[i] ~ /^\(.*\)$/ && gap[i] ~ /^\**[ ]$/) {
                    for (j = i - 1; j >= 1 && span[j] ~ /^[a-z][a-z0-9_]*$/; j--) {
                        print document ":" NR "\t" span[j] "\t" substr(span[i], 2, length(span[i]) - 2)
                        if (gap[j] !~ /^\**(, | and )\**$/) break
                    }
                }
            }
        }' "$root/$document"
    done
)"
while IFS=$'\t' read -r where name arguments; do
    file="$(find "$root/queries" -name "$name.sql" | head -n 1)"
    [ -n "$file" ] || continue
    code="$(sed 's/--.*//' "$file")"
    takes="$( { grep -o ':[a-z_][a-z0-9_]*' <<< "$code" | tr -d ':' || true; grep -o "slot = '[a-z]*'" <<< "$code" | cut -d"'" -f2 || true; } | sort -u | paste -sd' ')"
    written="$(tr ',' '\n' <<< "$arguments" | tr -d ' ' | sed '/^$/d' | sort | paste -sd' ')"
    if [ "$written" != "$takes" ]; then
        echo "$where: $name($arguments), where the statement takes ($takes)" >&2
        failures=$((failures + 1))
    fi
done <<< "$signatures"

# STORAGE.md Annex B's table names every capability the part defines, one a
# row, each lowercase words joined by periods, its first word the domain whose
# kind the row states, none in an application's x- space; a capability a
# document or a scenario names is one of them, and none is abbreviated.
capabilities="$(sed -n '/^| Capability | Kind | Needed by |$/,/^$/p' "$root/STORAGE.md" | tail -n +3)"
if [ -z "$capabilities" ]; then
    echo "STORAGE.md Annex B: no table of capabilities" >&2
    failures=$((failures + 1))
fi
while IFS='|' read -r _ name kind _; do
    name="$(tr -d ' `' <<< "$name")"
    [ -n "$name" ] || continue
    kind="$(sed 's/^ *//; s/ *$//' <<< "$kind")"
    case "$name" in
        mail.*) domain='`message/rfc822`' ;;
        contacts.*) domain='`text/vcard`' ;;
        calendar.*) domain='`text/calendar`' ;;
        collection.*) domain="the anchor's" ;;
        *) domain='' ;;
    esac
    if ! grep -qxE '[a-z][a-z0-9-]*(\.[a-z0-9-]+)+' <<< "$name" || [ "$kind" != "$domain" ]; then
        echo "STORAGE.md Annex B: $name, kind [$kind], is no name of a domain's" >&2
        failures=$((failures + 1))
    fi
done <<< "$capabilities"
defined="$(cut -d'|' -f2 <<< "$capabilities" | tr -d ' `' | sort)"
used="$(
    grep -ohE '`((mail|contacts|calendar|collection)(\.[a-z0-9-]+)+|x-[a-z0-9-]+|\.(add|update|remove|move|copy))`' \
        "${documents[@]/#/$root/}" | tr -d '`'
    grep -ohE ":capability='[^']*'" "$root/checks/invariants.sh" | cut -d"'" -f2 || true
)"
while read -r name; do
    if [ -n "$name" ] && ! grep -qxF "$name" <<< "$defined"; then
        echo "$name: a capability named outside STORAGE.md Annex B's table" >&2
        failures=$((failures + 1))
    fi
done <<< "$(sort -u <<< "$used")"

# Each part states its profiles in one table of its conformance section
# (STORAGE.md §17, SYNC.md §12, SEARCH.md §12), and every vector file is owed
# by a profile one of them names, so no file binds nobody.
owed=""
for spec in "STORAGE.md:reader producer owner" "SYNC.md:engine connector" "SEARCH.md:indexer query client"; do
    part="${spec%%:*}"
    table="$(sed -n '/^## [0-9]*\. Conformance$/,/^## [^C]/p' "$root/$part" | grep '^| ' | tail -n +3 || true)"
    profiles="$(cut -d'|' -f2 <<< "$table" | sed 's/^ *//; s/ *$//' | paste -sd' ')"
    if [ "$profiles" != "${spec#*:}" ]; then
        echo "$part: its conformance table names [$profiles], not [${spec#*:}]" >&2
        failures=$((failures + 1))
    fi
    owed="$owed$(awk -F'|' 'NF > 2 { print $(NF - 1) }' <<< "$table")"
done
for file in $(cd "$root/vectors" && ls -d *.json sync search/*.json | grep -vx manifest.json); do
    if ! grep -qF "$(basename "$file")" <<< "$owed"; then
        echo "vectors/$file: owed by no profile of a conformance table" >&2
        failures=$((failures + 1))
    fi
done

# section <document> <number>: the text of one numbered section, a top-level
# one with its subsections, a subsection alone.
section() {
    awk -v number="$2" '
        /^##+ / {
            inside = 0
            if (number ~ /\./) { if ($1 == "###" && $2 == number) inside = 1 }
            else if ($1 == "##" && $2 == number ".") { inside = 1; top = 1 }
            else if ($1 == "###" && top && index($2, number ".") == 1) inside = 1
            else top = 0
        }
        inside' "$root/$1"
}

# owed <profile>: the text of every section the profile's row of STORAGE.md
# §17 lists under Owes, a range `§a.b to §a.c` taken whole.
owed() {
    local row token first last minor
    row="$(grep "^| $1 | " "$root/STORAGE.md" | cut -d'|' -f4)"
    while read -r token; do
        [ -n "$token" ] || continue
        if [[ "$token" == *" to "* ]]; then
            first="${token%% to *}"; last="${token##* to }"
            for minor in $(seq "${first##*.}" "${last##*.}"); do
                section STORAGE.md "${first%.*}.$minor"
            done
        else
            section STORAGE.md "$token"
        fi
    done < <(grep -oE '§[0-9]+(\.[0-9]+)?( to §[0-9]+(\.[0-9]+)?)?' <<< "$row" | tr -d '§')
}

# A reader's and a producer's statements are each named in a section their
# profile owes (STORAGE.md §17), so a profile reading its row's sections meets
# every statement of its directories, and a row that forgets a section fails.
owed reader > "$dir/owed.read"
{ cat "$dir/owed.read"; owed producer; } > "$dir/owed.queue"
for profile in read queue; do
    [ -s "$dir/owed.$profile" ] || {
        echo "STORAGE.md §17: no row, or no section, for the profile running queries/storage/$profile/" >&2
        failures=$((failures + 1))
    }
    for file in "$root"/queries/storage/$profile/*.sql; do
        statement="$(basename "$file" .sql)"
        if ! grep -q "\`$statement[\`(]" "$dir/owed.$profile"; then
            echo "$statement: under queries/storage/$profile/ and named in no section its profile's row of STORAGE.md §17 lists" >&2
            failures=$((failures + 1))
        fi
    done
done

# The reading paths of GUIDE.md §1 quote the paragraphs a reader, then a
# producer, reads, by their bold lead-ins: each one quoted opens a paragraph
# of STORAGE.md, so a lead-in reworded there fails here.
paths="$(grep -E "^\*\*A (reader|producer)'s path" "$root/GUIDE.md" || true)"
if [ "$(grep -c . <<< "$paths")" != 2 ]; then
    echo "GUIDE.md §1: no reading path for a reader and for a producer" >&2
    failures=$((failures + 1))
fi
while read -r lead; do
    [ -n "$lead" ] || continue
    if ! grep -qF "**$lead.**" "$root/STORAGE.md"; then
        echo "GUIDE.md §1: a reading path quotes \"$lead\", which opens no paragraph of STORAGE.md" >&2
        failures=$((failures + 1))
    fi
done < <(grep -o '"[^"]*"' <<< "$paths" | tr -d '"')

# A version of a vector format a document states is the one its schema holds
# (vectors/schema/, the `const` of `v`): vectors/README.md lists every
# format's, SYNC.md §11 the sync cases', SEARCH.md §11 the search files'.
const() {
    grep -o '"v": { "const": [0-9]* }' "$root/vectors/schema/$1.schema.json" | grep -o '[0-9]*'
}
listed="$(grep -o 'The current versions: [^.]*\(\.json[^.]*\)*\.' "$root/vectors/README.md" | sed 's/^The current versions: //; s/\.$//' | tr ',' '\n' | sed 's/^ *//')"
for schema in "$root"/vectors/schema/*.schema.json; do
    format="$(basename "$schema" .schema.json)"
    case "$format" in
        sync) file="sync/" ;;
        search-*) file="search/${format#search-}.json" ;;
        *) file="$format.json" ;;
    esac
    stated="$(sed -n "s|^$file \([0-9]*\)$|\1|p" <<< "$listed")"
    if [ "$stated" != "$(const "$format")" ]; then
        echo "vectors/README.md states version [$stated] for $file, its schema holds [$(const "$format")]" >&2
        failures=$((failures + 1))
    fi
done
stated="$(grep -o 'one JSON file each, stating `v` [0-9]*' "$root/SYNC.md" | grep -o '[0-9]*$' || true)"
if [ "$stated" != "$(const sync)" ]; then
    echo "SYNC.md §11 states \`v\` [$stated] for vectors/sync/, its schema holds [$(const sync)]" >&2
    failures=$((failures + 1))
fi
stated="$(sed -n 's/.*`v` \([0-9]*\) for queries.json, `v` \([0-9]*\) for store.json, `v` \([0-9]*\) for chunks.json and `v` \([0-9]*\) for refresh.json.*/\1 \2 \3 \4/p' "$root/SEARCH.md")"
if [ "$stated" != "$(const search-queries) $(const search-store) $(const search-chunks) $(const search-refresh)" ]; then
    echo "SEARCH.md §11 states \`v\` [$stated] for queries.json, store.json, chunks.json and refresh.json, their schemas hold [$(const search-queries) $(const search-store) $(const search-chunks) $(const search-refresh)]" >&2
    failures=$((failures + 1))
fi

# The informative documents add no requirement (AGENTS.md §1): each says it is
# informative on its Status line and writes no key word.
for document in OVERVIEW.md GUIDE.md vectors/README.md conventions/gtd.md; do
    if ! grep -qE '^Status: (.*, )?informative' "$root/$document"; then
        echo "$document: no Status line calling it informative" >&2
        failures=$((failures + 1))
    fi
    if grep -nE '\b(MUST|SHALL|SHOULD|REQUIRED|RECOMMENDED|MAY|OPTIONAL)\b' "$root/$document" >&2; then
        echo "$document: an informative document above writes a key word" >&2
        failures=$((failures + 1))
    fi
done

# Direction one: a statement nobody names is dead or undocumented. Asked of the
# documents directly, since a one-word statement (hit, coverage) is not in the
# snake_case list above.
while read -r statement; do
    if ! grep -qx "$statement" <<< "$mentioned" && ! grep -q "\`$statement[\`(]" "${documents[@]/#/$root/}"; then
        echo "$statement: under queries/ and named in no document" >&2
        failures=$((failures + 1))
    fi
done <<< "$statements"

# Direction two: an identifier that looks like a statement and is not one.
while read -r name; do
    if ! grep -qx "$name" <<< "$statements" && ! grep -qx "$name" <<< "$known"; then
        echo "$name: named in a document, neither a statement nor a schema name" >&2
        failures=$((failures + 1))
    fi
done <<< "$mentioned"

# A backticked lowercase word of one part, `refcount`, is a table, a column, a
# statement or a member a vector format or a payload defines, else one of the
# words below, which the documents write as values, examples and names of
# things outside the store; so a misspelt column (`refcont`) is no word any
# document may write. A word joins the list only as what it is.
words="
    $(: values of the closed and open vocabularies the parts state)
    manual none partial full auto user default inbox archive drafts sent trash
    junk important individual group answered seen unread known unknown held
    encrypted unparseable cancelled refused unchanged destroyed draft all
    canonical related waiting someday high medium low null updated addr ok
    $(: kinds, parts, verbs and procedures the documents name in backticks)
    mail contact contacts calendar journal task file search pimdir vtodo read
    write load mutate upgrade drain enqueue submit cancel purge rename move
    update capture report stop link links names hashes ids filename time bytes
    put cover erase
    $(: the query language of SEARCH.md §8 and its examples)
    and or not before after today yesterday relevance simple sep
    $(: platform calls, protocol words and libraries)
    fcntl flock fstat fsync lockf lstat mmap openat renameat2 stat unlink synchronous
    getetag multiget multipart inline charset bm25 unicode61 base64 zoneinfo
    client importance
    $(: the parts of a time a document spells, and example values)
    hhmm mm a b c i n x z abc alice caf réunion work band delta bounded primary
    expected cbf29ce484222325 shift
"
while read -r word; do
    if ! grep -qxF "$word" <<< "$statements" && ! grep -qxF "$word" <<< "$known" && ! grep -qw -- "$word" <<< "$words"; then
        echo "\`$word\`: a backticked word that is no schema name, statement, vector field nor listed word" >&2
        failures=$((failures + 1))
    fi
done < <(grep -oh '`[a-z][a-z0-9]*`' "${documents[@]/#/$root/}" | tr -d '`' | sort -u)

# An item's properties are local (STORAGE.md §4.3, SYNC.md §3): no statement
# of the load and the write STORAGE.md §14 opens with, nor one SYNC.md names,
# reads item_property, so no property reaches a projection, a base or a push.
engine="$(
    { grep -o '`[a-z][a-z0-9_]*`' "$root/SYNC.md"
      sed -n '/^## 14\. Operations$/,/^\*\*The batch\.\*\*/p' "$root/STORAGE.md" | grep -o '`[a-z][a-z0-9_]*`'
    } | tr -d '`' | sort -u
)"
while read -r name; do
    file="$(find "$root/queries/storage" -name "$name.sql" | head -n 1)"
    if [ -n "$file" ] && sed 's/--.*//' "$file" | grep -qw item_property; then
        echo "$name: a statement of the load, the write or the sync part reads item_property, which no engine reads" >&2
        failures=$((failures + 1))
    fi
done <<< "$engine"
if [ "$(grep -c . <<< "$engine")" -lt 20 ]; then
    echo "STORAGE.md §14 and SYNC.md name fewer statements than the load and the write run" >&2
    failures=$((failures + 1))
fi

if [ "$failures" -gt 0 ]; then
    echo "$failures name(s) out of step between the documents and queries/" >&2
    exit 1
fi

echo "$(wc -l <<< "$statements") statements named, every backticked identifier resolves"
