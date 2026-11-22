# A smaller pimdir: the target

Read on 2026-11-22 at pimdir b5b9382 and io-pimdir 00727ba. Every figure below was measured that evening: the schema read whole, the statements prepared under SQLite's authorizer (280 of 280, scratch files under the session's scratchpad, to be copied to tools/ here on the first step), and the four CLIs and the Android app read for what they use.

## 1. What the readings say

- **No store column is dead.** Every column of the 24 store tables is read by at least one statement. Nothing shrinks by dropping columns: the structure itself has to merge.
- **The engine holds no SQL.** src/sync.rs, src/hub.rs, src/mutate.rs, src/rekey.rs and src/upgrade.rs read a `PimdirLoaded` and answer `PimdirWriteOp`s (15 kinds). Only src/client/write.rs maps them to rows, through `PimdirHub`. The store can be redrawn under that seam.
- **Search is a second, hidden seam.** src/client/search/compile.rs names store tables about 53 times in SQL built at run time, and the index's own statements read them through `ATTACH ... AS store`. Every store move carries its search half.
- **The count of statements comes from the shape, not from the features.** Six summary tables give about 45 statements (a get, a page, two loads, an upsert, a delete, a search for each kind); three list tables (`item_address`, `mail_in_reply_to`, `task_category`) give 13; two flag tables give 4 and 12 of the 43 triggers.
- **In the index, four things are kept up to date and read by nothing**: the `chunk` table, the `thread` table's `first`, `last` and `count`, seven statements (`flagged`, `attached`, `holding`, `categorised`, `occurring_between`, `chunks_of`, `set_extraction`). The bench speed comes from two structures of io-pimdir's own, outside the canonical schema: the index.hits file and the `pimdir_fields` table.
- **The oracle is good.** 71 of io-pimdir's 109 test files reach the store through the public API alone; the 200 sync vectors state logical rows (flags as arrays, summaries by kind) that a runner maps to SQL. 38 files are bound to the schema and follow each move.
- **The Android app is a second store layer**, in Java: 130 of the 211 canonical statements, 47 of them forked for SQLite 3.18, and 103 statements of its own. Its cost follows the tables and columns, not the count of statements. It is not ported tonight.
- **The four CLIs are not on io-pimdir's head.** himalaya pins dc19b8d, neverest b080e14, cardamum and calendula 0.19.1. None builds against 00727ba as it stands (a new field of `PimdirPlacement`, a new variant of `PimdirAction`, the split features, tests naming storage-draft-16). A regression is therefore measured between two ports of each: one to the head before the night, one to the head after.

## 2. The boundary

| | Today | After |
| --- | --- | --- |
| Store schema, migrations/storage/0001_init.sql | normative | normative: the tables, columns, constraints, triggers and views are the contract, and the document describes them |
| The 217 storage statements, queries/storage/ | normative by name, parameters, columns and effect | io-pimdir's own, under its sql/ |
| queries/signatures.json, checks/names.sh, checks/signatures.py, checks/waivers.txt | bind the statements | gone from pimdir; the signature listing follows the statements as io-pimdir's tooling |
| Index schema and its 63 statements, migrations/search/, queries/search/ | normative | io-pimdir's own: the index is derived, rebuilt and never migrated |
| The query language, tokens, extraction, calendar time, threads, what an answer states | normative, SEARCH.md | unchanged |
| The sync rules, SYNC.md, vectors/sync/ | normative | unchanged; a reference to a statement becomes a reference to the rows it names |
| Payload schemas, vectors/objects.json, payloads.json, summaries.json, versions.json | normative | unchanged, the summaries restated where a field moves |
| vectors/search/ | answers, and two index internals in refresh.json (`objects`, `split`) | answers only |
| generator/ | pimdir's, writing through the canonical statements | moves to io-pimdir with the statements it binds |
| checks/invariants.sh, 4,266 lines running statements by name | the store's oracle | retired, each scenario mapped first to the io-pimdir test that holds its rule, or ported as one |
| GUIDE.md, 19,844 words naming a statement at every step | informative | retired |

The schema keeps loading on SQLite 3.18, as STORAGE §4.1 asks: no STRICT, no generated column, no upsert in the schema itself.

## 3. The store, 24 tables to 15

Kept as they are: `store_meta`, `collections`, `sources`, `capabilities`, `performers`, `objects`, `supersessions`, `item_reference`, `item_property`, `queue`, `receipts`.

### 3.1 Flags are columns

`placement_flag` and `binding_base_flag` go. The flags other than the five system flags are one column on each side, the set as text: each flag printable and holding no space (the rule of today), sorted bytewise, joined by one space, `''` for none.

```sql
-- items
flags_known INTEGER NOT NULL DEFAULT 0,
marks       INTEGER NOT NULL DEFAULT 0,   -- the five system flags, as today
keywords    TEXT    NOT NULL DEFAULT '',  -- every other flag
CHECK (flags_known = 1 OR (marks = 0 AND keywords = ''))

-- bindings
base_flags_known INTEGER NOT NULL DEFAULT 0,
base_marks       INTEGER NOT NULL DEFAULT 0,
base_keywords    TEXT    NOT NULL DEFAULT '',
CHECK (base_flags_known = 1 OR (base_marks = 0 AND base_keywords = ''))
```

Every read already answers the set as a space-joined text, so readers change nothing. `binding_owes` compares two columns instead of two anti-joins. A keyword predicate stays answered by the index, as today (`placement_flag_by_flag` was kept under a waiver and seeks nothing). Gone with the tables: 12 triggers (`placement_flag_*` six, `binding_base_flag_*` four, `items_forget_flags`, `bindings_forget_base_flags`) and `add_flags`, `retain_flags`, `add_base_flags`, `retain_base_flags`.

### 3.2 One summary table

`mail_summary`, `contact_summary`, `event_summary`, `task_summary`, `journal_summary` and `file_summary` become `summary`, one row per item, the columns named as today where a kind owns them and shared where they already mean the same:

```sql
CREATE TABLE summary (
    item          INTEGER PRIMARY KEY REFERENCES items(id) ON DELETE CASCADE,
    component     TEXT NOT NULL,  -- mail | contact | event | task | journal | file
    uid           TEXT,           -- the identity the content states: Message-ID (bare) or UID
    title         TEXT NOT NULL,  -- subject | FN | SUMMARY | file name
    -- mail
    sender        TEXT,
    sender_name   TEXT,
    date          TEXT,
    size          INTEGER,        -- mail and file
    attachment    INTEGER,
    invitation    TEXT,
    -- contact
    card_kind     TEXT,           -- KIND
    org           TEXT,
    -- event, task, journal
    location      TEXT,
    dtstart       TEXT,
    dtstart_tzid  TEXT,
    dtstart_value TEXT,
    dtend         TEXT,
    recurring     INTEGER,
    until         TEXT,
    -- task
    due           TEXT,
    due_tzid      TEXT,
    due_value     TEXT,
    status        TEXT,
    completed     TEXT,
    percent       INTEGER,
    priority      INTEGER,
    parent        TEXT,
    mid           TEXT,
    created       TEXT,
    -- file
    media_type    TEXT,
    part          TEXT
);
```

Thirty-one columns, each with the type check and the value check it carries today. A mail row holds about twenty empty columns, a byte each: about 20 MB on the 1M bench store (pimdir.db is 1,787 MB there), measured in step 9. The three partial indexes follow (`invitation`, `parent`, `mid`). A calendar resource changing component is one upsert, so the three `delete_*_summary` go.

### 3.3 One table for a summary's lists

`item_address`, `mail_in_reply_to` and `task_category` become `summary_value`:

```sql
CREATE TABLE summary_value (
    item     INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE,
    role     TEXT    NOT NULL,  -- from to cc bcc email organizer attendee contact | in-reply-to | category
    position INTEGER NOT NULL,  -- document order within the role
    value    TEXT    NOT NULL,  -- canonical address | bare Message-ID | category
    name     TEXT,              -- an address's display name
    PRIMARY KEY (item, role, position)
) WITHOUT ROWID;
CREATE INDEX summary_value_by_value ON summary_value(value, role);
```

One index serves "everything about this address" and "who replied to this id".

### 3.4 Triggers, 43 to about 29

- Gone with the flag tables: 12.
- `store_meta_identity`: dropped, a guard against the owner's own statement (`raise_incarnation` only raises).
- `collections_keep_queued`: becomes `ON DELETE RESTRICT` on `queue.collection`, with the owner's check before the delete.

The stamps, the purge counters, the owing and lacking marks and the three cascades (`items_drop_references`, `item_reference_collects_files`, `items_drop_properties`) stay in the schema tonight. Moving the stamps and the marks to the writer would bring the count near 14, and costs every writer (io-pimdir, the app's Java, the generator) the protocol the schema now holds for them: it is measured tonight (step 9), not done.

### 3.5 Considered and left

- **Reference counts.** Collecting by an anti-join over the six pointer columns would drop `refcount` and its drift, but a batch must still know which bodies lost a pointer, so the diff stays and only the count goes. Data-loss class, small gain: not tonight.
- **Integer keys for collections and sources.** `items.collection` is the text id in the table and in seven indexes; a rename cascades through every row. Likely the largest density gain left, and it touches all 136 statements reading that column: measured tonight (dbstat on the bench store), proposed apart.
- **Queue and receipts in one table.** One foreign key cannot both restrict a pending row and outlive an applied one.
- **`supersessions` as a column, `performers` into `capabilities`.** Two tables for a small gain; stretch, last.

## 4. The statements

They move to io-pimdir/sql/ (storage/read, storage/queue, storage/owner, search), one file each as today, and `io_pimdir::sql` keeps exposing them by name: the Android app and neverest (`LOAD_CHECKPOINT`, `UPSERT_CHECKPOINT`, src/sync/storage.rs) read them there. Their count follows the structure: about 46 storage statements go with the merges above (217 to about 170), the 4 nothing references among them (`deliver_binding`, `link_senders_of_by_link`, `list_garbage_objects`, `set_store_version`); 7 search statements go (63 to 56 or fewer). The standard lists none.

## 5. The index, 13 tables to 10

Private to io-pimdir from tonight, so its shape is free:

- `chunk` goes: written for every body, read by nothing (snippets cut their own). vectors/search/chunks.json stays, as the rule it is.
- `thread` goes: `message.thread` keeps the thread id, `THREAD_SPAN` already reads the span from the store.
- `missing` becomes a column of `placement`.
- `object.attachment`, `tel`, `adr`, `bday`, `photo` stay five columns (clear, a byte each).
- `flag`, `occurrence`, `message`, `split`, `object`, `object_category`, `object_text`, `summary_text`, `index_meta` stay, and so do `pimdir_fields` and index.hits, which carry the bench.
- The seven dead statements go.

The index reads the store's new tables: `summary` and `summary_value` where it read the six summaries and the three lists, `items.keywords` where it read `placement_flag`.

## 6. The documents

| | Today (words) | Target |
| --- | --- | --- |
| STORAGE.md | 39,318 | at most 18,000: §14 "Operations" and every statement table leave; each section describes rows and rules |
| SEARCH.md | 12,966 | at most 8,000: §2 to §4 (index shape, statements, refresh procedure) leave; §5 to §10 stay |
| SYNC.md | 19,059 | unchanged but for its references |
| OVERVIEW.md | 6,197 | updated |
| GUIDE.md | 19,844 | retired |

STORAGE.md holds 212 requirement words (114 MUST, 41 MUST NOT, 26 SHOULD, 28 MAY, 2 SHALL, 1 SHOULD NOT). The rewrite goes through a ledger, rules.tsv here: one line per requirement sentence of today, marked kept (with its new section), moved (to io-pimdir's cairn/spec, as an implementation's own rule) or dropped (with the reason). No requirement leaves without a line. The owner reads the ledger's `dropped` and `moved` lines in the morning, not 39,000 words.

## 7. What gates a move

Not edited tonight, whatever a move asks: src/sync.rs, src/hub.rs, src/mutate.rs, src/rekey.rs, src/upgrade.rs, src/remote.rs, src/change.rs, src/load.rs, src/coroutine.rs, src/placement.rs, and the 200 files of vectors/sync/. A move that needs one of them edited stops and is listed for the owner.

A move is done when all of these hold, then it is checkpointed:

1. io-pimdir: `cargo test --all-features`, no failure the baseline did not have. A test is deleted only with the structure it tested, and listed in the journal.
2. The sync vectors: 200 of 200, the files untouched (the runner tests/vectors_sync.rs maps their rows to the new tables).
3. The search vectors: every answer of vectors/search/queries.json unchanged.
4. The generated tests (reader, overlay, drain, index refresh equal to rebuild, replay, crash), the generator following the move.
5. pimdir's remaining checks (`nix flake check path:$PWD`).

At the end of the storage moves and at the end of the night: clippy with `-D warnings`, `cargo fmt --check`, the no_std build (`cargo test --no-default-features --lib`), and the four CLIs' suites.

## 8. The consumers

Not ported tonight (owner, at the start of the night). For each of neverest, himalaya, cardamum and calendula, consumers.md lists what it names that moved: tables and columns in its tests (`mail_summary`, `event_summary`, `item_address`, `store_meta`, `queue`, `index_meta`, `placement_by_link`), statement names (neverest's `LOAD_CHECKPOINT` and `UPSERT_CHECKPOINT`), format strings, public items. Before the night none of them built against io-pimdir's head anyway (§1).

For the Android app, android.md here: each statement it binds and each table and column its own 103 statements name, with what became of it.
