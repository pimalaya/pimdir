# Pimdir search specification

Status: search-draft-08, requiring storage-draft-08

The search part of the pimdir standard: a full-text index over a store ([STORAGE.md](./STORAGE.md)) and the query language over it, cross-domain.

A query names people, dates, tags, kinds and text, and answers with items of every kind: a person's card, the mail they sent and the meetings they attend are one result set.

An implementation MAY omit search. One that offers it MUST conform by a profile of §12, vectors/search/ being the bar, so every client on one store answers `is:unread from:jane` the same way.

The index presupposes the store, and is built from it and rebuilt at will (§1).

[OVERVIEW.md](./OVERVIEW.md) §10 explains the model; [GUIDE.md](./GUIDE.md) §15 runs the refresh and the query as procedures. Both are informative and this part wins on any disagreement.

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in BCP 14 (RFC 2119, RFC 8174) when, and only when, they appear in all capitals, as shown here. Every statement of behaviour in this part is normative: a key word marks its requirement level, and a statement carrying none binds as one carrying MUST. Notes, examples and rationale are informative and marked as such: a paragraph opening with *Note:*, an instance of what a sentence states given in parentheses or after "for example", and a reason given with "so", "since" or "because", none of which adds a requirement. §n of STORAGE.md is written STORAGE §n.

## Contents

1. [Scope](#1-scope)
2. [Requirements](#2-requirements)
3. [The index](#3-the-index)
4. [Refresh](#4-refresh)
5. [Tokens](#5-tokens)
6. [Extraction](#6-extraction)
7. [Calendar time](#7-calendar-time)
8. [The query language](#8-the-query-language)
9. [Threads](#9-threads)
10. [Tags](#10-tags)
11. [Test vectors](#11-test-vectors)
12. [Conformance](#12-conformance)

## 1. Scope

The store answers the structured questions itself: a sender, a date range, a name, a flag, everything about an address (STORAGE §14.1, Annex A.6). The index adds what it cannot: text, calendar time across a recurring series, threads, and what a card holds.

A query composes both: a structured predicate is a seek on the store, a text predicate a match on the index, and the result is their intersection in the store's own order.

The index is derived. Every row is recomputed from the store and the bodies, and dropping index.db loses nothing.

## 2. Requirements

- The index MUST be a SQLite database named index.db in the store directory (STORAGE §3), `PRAGMA foreign_keys = ON`, `PRAGMA journal_mode = WAL` RECOMMENDED so query clients read while a refresh writes.
- The **canonical shape** is [migrations/search/0001_init.sql](./migrations/search/0001_init.sql) and the statements under queries/search/, every table `STRICT`, and is the RECOMMENDED one. It needs **SQLite ≥ 3.43** with FTS5, for `contentless_delete`, a floor above the store's.
- An index of another shape (FTS4, FTS3, or no full-text module) MAY answer the same language: every query's hit set is the one vectors/search/ gives, its text folded as §5 says and its text terms matched as §8.5 says. Its order by relevance is its own (§8.2), and so is how it keeps itself current.
- **The hit-set guarantee leaves out text reduced from HTML, and a part's text beyond seven-bit ASCII in a charset other than UTF-8.** §6 pins neither how a `text/html` part becomes text nor, but as a recommendation, how another charset is decoded, so a word that text alone holds MAY be a hit in one conforming index and not in another. The vectors hold no such word.
- **An index names its version and its shape.** Whatever its shape, an index holds a one-row table `index_meta` whose `format` is `pimdir-index`, whose `format_version` names the version of this part it follows, this draft's name, `search-draft-08`, while this part is a draft and `search-vN` once released (N its major), and whose `shape` names its shape: `canonical` for the canonical one, written by `init_index_meta`, and a name of the implementation's own for another, never `canonical`. Versions are ordered: drafts by their number, every draft below every release, releases by their major.
- **An indexer rebuilds only an older index of its own shape.** An indexer MUST refuse an index.db holding no `index_meta`, one whose `shape` is not its own, and one whose `format_version` lies above its own, naming the index's version and shape and its own, and MUST NOT rebuild, write nor delete it: a person deleting index.db hands the store to another indexer, losing nothing (§1). An index of its own shape whose `format_version` lies below its own, and one whose `index_meta` lacks `format_version`, which a draft before search-draft-08 wrote and whose indexer refuses this draft's store (STORAGE §4.2), MUST be rebuilt: there are no index migrations.
- An index of the indexer's own shape and version MUST also be rebuilt when its `index_meta.tokenizer` differs from §5's, its schema text from 0001_init.sql's (the canonical shape), when it was built from another store or another copy of it, or when its `store_change` lies above the store's last stamp. `index_meta.store_id` and `store_incarnation` record the store's `store_id` and `incarnation` when the index was created (`init_index_meta`), and a store answering others is another (STORAGE §4.5).
- **A query client reads only an index it implements.** It MUST refuse an index whose `shape` or `format_version` it does not implement, naming both, rather than answer from it; while this part is a draft it implements its own draft alone, as STORAGE §4.2 has a program open only its own draft's store.
- The canonical schema's version is the index's own `PRAGMA user_version`, mirrored in `index_meta.version`. While this part is a draft a schema change is folded into 0001_init.sql, the version staying 1, `format_version` telling one draft's index from another's.
- The schema text is compared object by object: each table, index and trigger 0001_init.sql creates, by name, against the index's own by its `sqlite_master` text, `--` comments removed and whitespace collapsed, the shadow tables FTS5 creates and a table of the implementation's own beside them left out.
- The statements are under [queries/search/](./queries/search/), one file per statement named after it, prepared with the store attached read-only as `store`; §3 names each and the profile that runs it.

## 3. The index

The **indexer** is a store reader (STORAGE §8): read-only on pimdir.db, no store lock, running whether or not an owner syncs.

It is the sole writer of index.db and MUST hold an exclusive advisory lock on index.lock for a refresh, on the owner lock's terms: taken whole-file with `flock(2)` on Unix or `LockFileEx` on Windows, never an `fcntl` record lock (STORAGE §8).

**Query clients** open index.db read-only, any number at once, no lock.

The main database is index.db, pimdir.db attached as `store` through a read-only URI, so one statement joins both (`hit`, `coverage`).

Tagging is a store write through the queue (§10). Nothing writes the store through the index. References (STORAGE §14.2) are read from the store by `linked`, never copied into the index.

The index holds:

- one `object` row and one `object_text` FTS row per indexed body, keyed on the store's hash, so a body filed in three collections is tokenised once;
- one `placement` row per live item seen, with where its occurrences were cut (§7);
- a `summary_text` row per placement with no body;
- a `missing` row per placement whose body could not be read (§4);
- the derived `flag`, `occurrence`, `thread`, `message` and `chunk` tables;
- `index_meta`: its version and shape and the store it was built from (§2), the store cursors folded in (§4), the horizon and the time zones the occurrences stand under (§7).

**Statements.** Each statement under queries/search/ is named here with the profile that runs it: the indexer, a query client, or both. A statement's name, its named parameters and the columns it answers bind on STORAGE §4.4's terms.

| Statement | Profile | § |
| --- | --- | --- |
| `init_index_meta` | indexer | §2 |
| `load_index_meta` | both | §2, §4, §7 |
| `load_changed_items` | indexer | §4 |
| `load_missing_items` | indexer | §4 |
| `insert_missing` | indexer | §4 |
| `delete_missing` | indexer | §4 |
| `object_indexed` | indexer | §4 |
| `insert_object` | indexer | §6 |
| `insert_object_text` | indexer | §6 |
| `insert_object_category` | indexer | §6 |
| `insert_chunk` | indexer | §6 |
| `upsert_placement` | indexer | §4 |
| `delete_placement` | indexer | §4 |
| `insert_summary_text` | indexer | §6 |
| `delete_summary_text` | indexer | §4 |
| `replace_flags` | indexer | §4 |
| `insert_flag` | indexer | §4 |
| `replace_occurrences` | indexer | §7 |
| `insert_occurrence` | indexer | §7 |
| `set_cut` | indexer | §7 |
| `items_to_reexpand` | indexer | §7 |
| `set_horizon` | indexer | §7 |
| `set_tzdb_version` | indexer | §7 |
| `set_floating_zone` | indexer | §7 |
| `upsert_message` | indexer | §9 |
| `upsert_thread` | indexer | §9 |
| `unparent_messages` | indexer | §9 |
| `prune_messages` | indexer | §9 |
| `thread_rows` | indexer | §9 |
| `delete_thread` | indexer | §9 |
| `placements_gone` | indexer | §4 |
| `objects_gone` | indexer | §4 |
| `delete_object` | indexer | §4 |
| `delete_object_row` | indexer | §4 |
| `set_index_cursor` | indexer | §4 |
| `optimize_text` | indexer | §4 |
| `thread_of` | both | §9 |
| `match_objects` | query client | §8.5 |
| `match_summaries` | query client | §8.5 |
| `match_objects_ranked` | query client | §8.2 |
| `match_object` | query client | §8.2 |
| `match_summary` | query client | §8.2 |
| `flagged` | query client | §8 |
| `attached` | query client | §8 |
| `holding` | query client | §8 |
| `categorised` | query client | §8 |
| `linked` | query client | §8 |
| `occurring_between` | query client | §8.1 |
| `occurrences_between` | query client | §7 |
| `thread_members` | query client | §9 |
| `hit` | query client | §8.2 |
| `chunks_of` | query client | §6 |
| `coverage` | query client | §8.2 |
| `cut_before` | query client | §8.2 |
| `behind` | query client | §8.2 |

## 4. Refresh

Before a pass the indexer reads the store's cursor and identity (`load_change_cursor`) and rebuilds the index where §2 says: one built from another store or another incarnation, or whose `store_change` lies above the store's last stamp, has folded what the store no longer holds, a reset (STORAGE §4.5).

A refresh folds the change feed (STORAGE §4.5): every item stamped above `index_meta.store_change`, the last stamp drawn when the previous pass began, in stamp order, in read transactions of bounded size so the store's WAL still checkpoints.

An owner keeping an index SHOULD refresh it after each write batch it commits (STORAGE §14), so a client reading its rows from the store and its filters from the index finds the two at most one batch apart. The lag stays part of every answer all the same (`behind`, §8.2).

Per row:

- the body is indexed if its hash is new (§6);
- the placement is upserted;
- summary text is written while it has no body and dropped when it gains one;
- flags are replaced;
- occurrences are re-expanded when the body changed (§7);
- the thread is updated (§9).

A deleted row loses its placement, which takes its flags and occurrences by cascade. The indexer deletes its summary text by the rowid the delete returns. Its body's text stays until the object goes. A mail placement that was its link id's last prunes its thread (§9) in the same transaction.

**A body that cannot be read is tried again.** A body the blob directory no longer holds when the indexer opens it, or whose bytes fail its name (STORAGE §7), is not `unparseable`: no `object` row is written, the placement is indexed as a bodiless one (its `hash` `NULL`, its summary text written) and recorded in `missing` (`insert_missing`). Every pass first folds the recorded placements again (`load_missing_items`, which answers each as `load_changed_items` does), whether or not the store stamped them again, since a body fetched again under the same name after a quarantine restamps nothing. A placement whose body is indexed leaves `missing` (`delete_missing`), as does one holding no body any more, and one the store no longer holds goes with its placement.

**Keys are reconciled when the purge count moved.** `store_meta.purges` counts purged items, collected objects and renamed collections alike (STORAGE §4.5): when it moved from `index_meta.store_purges`, `placements_gone` and `objects_gone` name what the store no longer holds, a renamed collection's old placements among them, and the indexer deletes them, pruning the thread of every mail placement that was its link id's last (§9).

The cursor read before the pass is written by `set_index_cursor` in the transaction completing it, as `store_change`, with the purge count read beside it. A crash thus replays and skips nothing.

A batch MAY record its last row's stamp (`load_changed_items` answers each row's) as `store_change` in its own transaction, the purge count left as the last completed pass recorded it. A crash, or a pass a deadline cuts short, then resumes after the last batch committed and still reconciles: a batch folding a rename's restamped items moves `store_change` past them, and `store_purges` alone stays below the store's count until a pass completes.

**Erasing.** Every connection writing index.db sets `PRAGMA secure_delete = ON` (STORAGE §11.5). The tokens of a deleted body or summary stay in the full-text segments until they merge, so a refresh deleting what an erasure purged (STORAGE §11.5) is followed by `optimize_text`, which merges every segment of `object_text` and `summary_text` into one, and an index of another shape merges its own the same way.

Extraction MAY run in parallel; the index is written by one transaction per batch.

## 5. Tokens

**Text is folded before any tokenizer reads it**, in the index and in a query alike: every character lowercased by STORAGE Annex A.2's mapping, then decomposed (Unicode canonical decomposition, NFD), every combining mark of U+0300 to U+036F dropped, and composed again (NFC). `Réunion`, `REUNION` and `réunion` are one word, and a mark of another block (a Devanagari vowel sign, a Hebrew point) is kept. The indexer writes folded text and the query compiler folds every text term, so no tokenizer folds a diacritic and no SQL function is registered. What is left to a tokenizer is splitting words: FTS5's and FTS4's `unicode61` split alike, with diacritics kept (`remove_diacritics 0`, FTS4's `remove_diacritics=0`). One splitting otherwise, FTS4's `simple` splitting on ASCII alone, answers other hit sets, and a shape using it answers the vectors all the same.

The canonical tokenizer is `unicode61 remove_diacritics 0`, no stemming, no trigram substring search, `prefix = '2 3'` for the trailing wildcard (§8), recorded in `index_meta.tokenizer`.

An address is indexed whole, as its local part and as its domain in the `people` field, so `alice`, `example.org` and `alice@example.org` all match and `from:@example.org` is a match rather than a scan. A telephone number is indexed as its digits alone beside the value.

## 6. Extraction

A body is extracted once, by hash, into seven fields: `title`, `people` (every name and address, plus §5's address tokens), `body`, `attachment` (part names and media types), `place`, `org`, `note`.

Beside `people`, one field per address role of STORAGE Annex A.6 (`from`, `to`, `cc`, `bcc`, `email`, `organizer`, `attendee`) holds that role's names and addresses alone, so `from:jane` is a match on the sender and not on anyone the message names.

| Kind | `title` | `people` | `body` | `attachment` | `place` | `org` | `note` |
| --- | --- | --- | --- | --- | --- | --- | --- |
| mail | `Subject` | `From`, `To`, `Cc`, `Bcc` | the text parts | its attachments' names and media types (STORAGE §14.3) | | | |
| contact | `FN`, `N` components, `NICKNAME` | every `EMAIL`, the `FN` | | | `ADR` | `ORG`, `TITLE`, `ROLE` | `NOTE`, every `TEL` |
| calendar | `SUMMARY` | `ORGANIZER`, `ATTENDEE` values and `CN`s | `DESCRIPTION` | each `ATTACH`'s `FILENAME` (RFC 8607) and `FMTTYPE`, an `ATTACH` stating neither adding nothing | `LOCATION` | | `COMMENT` |

The body's `object` row records whether the extraction wrote any text into the `attachment` field (`object.attachment`, 1 or 0, written by `insert_object`). `has:attachment` thus reads a calendar item by a seek (`attached`): `object_text` is contentless and keeps no text to test, and no statement here reads its shadow tables, FTS5's own format.

A card's row also records whether it holds a `TEL`, an `ADR`, a `BDAY` and a `PHOTO` (`object.tel`, `object.adr`, `object.bday`, `object.photo`, 1 or 0, every other kind's 0), so `has:phone`, `has:address`, `has:birthday` and `has:photo` read a card by a seek (`holding`). Its `CATEGORIES` values are recorded beside it, each property's list split on unescaped commas and decoded as STORAGE Annex A.4 splits a task's, empty values dropped, folded as Annex A.2 folds `fn`, each once (`object_category`, `insert_object_category`), so `category:` reads a card by a seek (`categorised`) as it reads a task on `task_category`.

Mail extraction MUST walk the MIME tree as STORAGE Annex A.1 bounds the walk, reading no part it leaves unread, decode transfer encodings, decode each text part by its `charset`, decode RFC 2047 and RFC 2231, prefer `text/plain` and reduce `text/html` to text. The reduction is the implementation's own, which this part does not pin, and text so reduced is outside the hit-set guarantee (§2).

A text part SHOULD be decoded as STORAGE Annex A.1 decodes an encoded word's octets, by the WHATWG Encoding Standard's decoder for the encoding its `charset` labels, no byte order mark sniffed, `us-ascii` when it states none (RFC 2046 §4.1.2), and as UTF-8 replaced as Annex A.0 says when no label names one. Its text beyond seven-bit ASCII in a charset other than UTF-8 is outside the hit-set guarantee (§2). Attachment content is out of scope.

A `multipart/encrypted` or `application/pkcs7-mime` body is recorded `encrypted`, headers indexed and body not. Decrypted content is indexed only when the user asks for it, never by default: it writes the plaintext into index.db (STORAGE §18).

A body no parser accepts is `unparseable`, with what could be read.

Extraction MUST record the chunk boundaries of the `body` and `note` fields, one `chunk` row per chunk (`insert_chunk`), numbered from 0 in text order, the `body` field's before the `note` field's, and bounded by UTF-8 byte offsets into the field's text:

- **Paragraphs.** A field's text is split into paragraphs at every blank-line run: a line break (LF, or CR LF) followed by one or more lines holding nothing but spaces and tabs, each ended by a line break.
- **Packing.** Paragraphs are packed greedily, in order, into chunks of at most 1024 bytes, a chunk running from its first paragraph's start to its last one's end, the runs between them included. A paragraph that does not fit the chunk being filled starts the next one.
- **Long paragraphs.** A paragraph longer than 1024 bytes is cut into pieces, each ending just after the last space, tab, CR or LF within its first 1024 bytes, else at the last character boundary within them. Every piece but the last is a chunk of its own, and the last is packed as a paragraph.

The chunks thus cover the text but its blank-line runs, a field of blank lines alone having none. Other fields are not chunked; a summary row has no chunk.

A snippet is cut from a hit's chunks (`chunks_of`), and an embedding index embeds the same ones without extracting again.

The offsets index the text as the indexer extracted it, before §5's fold, which is stored nowhere, and §6 pins neither `text/html` reduction nor the decoding of every charset. A query client re-extracts the field from the blob to cut a snippet. One whose extraction is not the indexer's implementation MUST re-chunk its own text by the rule above rather than apply the stored offsets to it.

A placement with no body indexes its summary row and address rows into `summary_text`: `title` from the subject, `fn`, `summary` or a file's `name`, `people` and the role fields from the addresses. The `summary_text` row is dropped once the body is indexed (§4).

A file (STORAGE §14.3) is indexed from its summary alone, its body or not: its content is out of scope, as attachment content is. Every value is decoded on Annex A.0's terms.

## 7. Calendar time

`sort_key` holds a series' first occurrence (STORAGE Annex A.3), so `date:today` cannot be answered from the store for a meeting that started years ago.

The index materialises every occurrence within a **horizon**, default one year back and two forward, into `occurrence(start, end)` as instants, using the resource's `VTIMEZONE`s, `RDATE`, `EXDATE` and `RECURRENCE-ID` overrides:

- An event spans `DTSTART` to `DTEND` or `DURATION`, and with neither one day for a date and no time for a date-time (RFC 5545 §3.6.1).
- A task spans to its `DUE`, a task with a `DUE`, no `DTSTART` and no `RRULE` being one zero-length occurrence at its due time.
- A journal spans its `DTSTART` alone.
- A resource holding overrides and no master, as an attendee invited to a single instance stores it, yields each override as an occurrence, spanning its own `DTSTART` to its end by the rules above.
- A series no expander accepts (an `RRULE` with no `DTSTART`) yields no occurrence and MUST NOT fail the pass.

**Bounds.** An item writes at most 10,000 occurrences: the first, in the order `start` then `end`, of those overlapping the horizon. An expander examines at most 1,000,000 periods of a recurrence rule, a period being each span of `INTERVAL` times the rule's `FREQ` in turn from the one holding its `DTSTART` (RFC 5545 §3.3.10), whether or not it yields an instance, so a rule stepping by the second or whose `BYxxx` parts seldom match ends there; a period before the horizon counts. An item either bound stops records its **cut** with its occurrences (`set_cut`): the instant from which its occurrences are not all written, the earlier of the start of its 10,001st occurrence and the start of the first period not examined, `NULL` when neither bound stops it. Every occurrence starting before the cut is written. A `VTIMEZONE` observance's rule is examined on the same bound, the offset of the last onset found standing beyond it, and cuts nothing.

A zoned time resolves through the resource's own `VTIMEZONE`, else the IANA time zone database by `TZID`, else as floating, the same order as STORAGE Annex A.3. A wall time a transition makes ambiguous or skips, a recurrence instance's included (RFC 5545 §3.3.10), takes the offset in effect before the transition, as there: the earlier of two instants, and a skipped one read at the offset before the gap. A floating time and a date are read in the time zone the indexer states, an IANA name, `UTC` when it states none, as §8.1 reads a query's dates. `index_meta.floating_zone` records the zone they were read in, `UTC` when the index is created.

A range's occurrences are listed by `occurrences_between`, one row each with its instants, in the order `start`, then `seq`, then `collection`, on §8.1's overlap rule, an occurrence of zero length falling in the range it starts. A client drawing calendar time over a range, an agenda, reads them there and the summary rows of their items from the store (STORAGE Annex A), a body only to open one; a range outside the horizon, or reaching past an item's cut, is incomplete there as it is in a query's coverage (§8.2).

An item is re-expanded when its body changes, when the horizon rolls, and when the time zone database or the indexer's zone changes.

The roll re-expands the recurring items whose `until` is absent or not before the old horizon's end, and expands the single items whose start the new window covers and the old one did not (`items_to_reexpand`, bound to both horizons before `set_horizon` records the new one). A query outside the horizon MUST say so in its coverage (§8).

A zoned time resolved through the time zone database moves when the database does. `index_meta.tzdb_version` records the version the occurrences were expanded under, as the database names its release (IANA's `2026b`), empty with none.

An indexer whose database names another version MUST re-expand every live calendar item and record the new version (`set_tzdb_version`) in the pass that sees it: `items_to_reexpand`, bound to that version, returns every live calendar item when it is not the recorded one, the horizon bound twice when it did not roll.

An indexer stating another zone than `floating_zone` records MUST likewise re-expand every live calendar item and record its zone (`set_floating_zone`) in the pass that sees it: `items_to_reexpand`, bound to the zone too, returns every live calendar item when it is not the recorded one, so two indexers in two zones never leave rows read in both.

## 8. The query language

A query is whitespace-separated terms, implicitly conjoined, with `or`, `not`, parentheses and quoted phrases; a term is free text or `field:value`; a trailing `*` is a prefix wildcard. Free text matches every field of §6.

§8.3 is the grammar and §8.4 the answer to a query it refuses. A full-text engine's own syntax (FTS5's, FTS4's) is never accepted raw, and §8.5 says how a text term becomes a match.

| Field | Meaning |
| --- | --- |
| `subject:` `title:` `summary:` | the `title` field |
| `body:` | the `body` field |
| `from:` `to:` `cc:` `bcc:` `attendee:` `organizer:` `email:` | the role's `item_address` seek for a value containing `@` (a bare `@domain` seeks the domain), the role's own field otherwise |
| `with:` | any role, the same way over the `people` field |
| `person:` | contacts whose `title` matches, expanded to `with:` over their `email` rows |
| `tag:` `flag:` | a store flag (§10), as written |
| `is:` | `unread` the absence of `\Seen`; `read`, `flagged`, `answered`, `draft` the presence of `\Seen`, `\Flagged`, `\Answered`, `\Draft`; `encrypted` the extraction status (§6) |
| `has:body` `has:attachment` | a stored body; a message whose `mail_summary.attachment` is 1, the mark read with or without its body (STORAGE Annex A.1), or a calendar item whose body's `attachment` field (§6) is non-empty, as `object.attachment` records it (`attached`); a contact or a file never |
| `has:phone` `has:address` `has:birthday` `has:photo` | a card holding a `TEL`, an `ADR`, a `BDAY`, a `PHOTO`, as its body's `object` row records it (§6, `holding`); any other kind never |
| `kind:` | `mail`, `contact`, `event`, `task`, `journal`, `file` |
| `status:` | a task's `STATUS` (`task_summary.status`): `needs-action`, `in-process`, `completed`, `cancelled`; a task stating none, and any other kind, matches none |
| `priority:` | a task's `PRIORITY` (`task_summary.priority`, RFC 5545 §3.8.1.9): `high` 1 to 4, `medium` 5, `low` 6 to 9, `none` absent or 0; any other kind matches none |
| `category:` | a task's `CATEGORIES` (`task_category`) or a card's (`object_category`, §6, `categorised`): one value whole, both sides folded as STORAGE Annex A.2 folds `fn`, never a word of it; any other kind never |
| `account:` `collection:` `folder:` | the store's axes, `folder:` an alias |
| `date:` `when:` | an instant or a range (§8.1) |
| `thread:` `id:` | a thread id (§9); a link id or a `seq`: a value of ASCII digits alone names the item of that `seq` and every item whose link id it is, a hit set rather than a guess, any other value a link id |
| `linked:` | the items at the other end of the named item's references, either direction (`linked`): `linked:<id>`, or `linked:<role>:<id>` for one role of STORAGE §14.2, the item named as `id:` names it, with every kind it is held under; the text before the value's first colon is a role when it is one of STORAGE §14.2's, named or `x-` and a name, and the rest the id, else the whole value is the id, so an id beginning with such a role and a colon is named with its role written |
| `attachment:` `mimetype:` | the `attachment` field |
| `location:` | the `place` field |
| `changed:` | change stamps over `items.changed` (STORAGE §4.5), a stamp or a range, both ends included |

### 8.1 Dates

A `date:` or `when:` value is a point or a range of points (`date-value`, §8.3):

- A year, a month, a day, `today` and `yesterday` each cover their calendar span, in the time zone the client states, UTC when it states none.
- A relative amount (`3d`, `2w`, `1y`: days, weeks of seven days, calendar years) names the instant that long before `now`.
- A single point is its span, a single relative amount the span from its instant to `now`.
- A range `a..b` runs from the start of `a`'s span to the end of `b`'s, either side open.

Every span is half-open.

- Mail compares `sort_key`.
- An event, task or journal compares occurrences (§7), an occurrence overlapping a half-open range when it starts before the range ends and ends after the range starts, a zero-length one when it starts inside it.
- A contact or a file has no date, a file's `sort_key` being its name, and is excluded from a date-bounded query unless `kind:contact` or `kind:file` names it.

A range leaves the horizon when it starts before the horizon's start or ends after its end, an open side always, and only in a query whose kinds and collections can hold a calendar item. The horizon bounds occurrences alone, so a query reaching mail, contacts or files alone, by `kind:` or by its collections, never leaves it.

### 8.2 Semantics

- **A hit is `(account, seq)`**, one per item per account, carrying its placements (STORAGE §9.2). An implementation MAY flatten to one row per placement on request.
- **Tags** are per placement in the store and per hit in the query: `tag:x` matches when any placement carries `x`, `not tag:x` when none does.
- **Order** is `sort_key` descending by default, the undated last (contacts and files) in their own `sort_key` ascending; `name` the item's title (a message's subject, a card's `fn`, a calendar component's summary, a file's name) folded as Annex A.2 folds `fn`, ascending, a title-less item first; `relevance` the shape's own, best first, bm25 RECOMMENDED and the canonical shape's (FTS5 `bm25`); a shape without one MAY refuse `relevance` and say so. Ties go to `seq`, then the account.
- **Deleted items are excluded.** The trash is the store's (STORAGE §11), not the index's.
- **Coverage is part of the answer**:
  - per kind, how many live items of the query's collections have no body, among the kinds whose body search reads, mail, contacts and calendars, never files (§6): `coverage`, bound to those collections;
  - whether a date range left the horizon (§8.1);
  - for a query bounded by date, how many calendar items of its collections had their occurrences cut before the range's end (§7): `cut_before`, its end `NULL` for a range open there;
  - how far the index lags the store;
  - per hit, whether it matched on its body or its summary.
- **The lag, `behind`**, is store-wide: the stamps the store drew above `index_meta.store_change` (`behind`). It is zero exactly when the index has folded every change, else an upper bound on the rows a refresh has yet to fold, since a row changed twice draws two stamps. A purge draws none, and a hit the store no longer holds is never answered (§1). A one-shot answer says it.
- **Coverage has a temporal axis**: whether the store holds every member of the queried collections over the query's date range, open on a side the query does not bound, read from their sources' coverage (STORAGE §10, `list_coverage`). It is `full`, or `bounded` with:
  - `since`, the instant below which a queried collection is not known complete (a `covered_since` above the range's start, `null` when no floor is the cause);
  - `until`, the instant from which one is not (a `covered_until` below the range's end, `null` likewise);
  - `filling`, true when a source of a queried collection never closed a round, so nothing there is known complete.
- A collection no source syncs is complete. The collections' temporal answers roll up conservatively: the highest `since`, the lowest `until`, `filling` when any is.
- A snippet is re-read from the blob for the hits shown, from their chunks (§6).
- **A page.** A client MAY answer the first hits in the query's order after a cursor, the last hit it answered, rather than every hit, and every page walked to the end answers the hits and the order one whole answer does. Two forms read a page without reading every hit:
  - **The store's order.** Walking the store's pages (STORAGE §9.3, §14.1) under the query's structured terms and testing each item's text terms on the index, its body by `match_object` and a bodiless placement's summary by `match_summary`, stops at the page, the store's keyset cursor resuming it. It suits a text term matching many items; one matching few is read first (`match_objects`, `match_summaries`) and ordered.
  - **Relevance.** `match_objects_ranked` reads the bodies a text term matches best first, a page of them at a time, and the client keeps the hits the query's other terms hold until its page is full.

### 8.3 Grammar

The query is a string of Unicode scalar values, read under this ABNF (RFC 5234, with RFC 7405's `%s` for a case-sensitive string and `%i` for an insensitive one), the rules from `query` to `primary` over the tokens the others spell:

```abnf
query        = [ disjunction ]           ; over tokens, every sep dropped
disjunction  = conjunction *( OR conjunction )
conjunction  = negation *( [ AND ] negation )
negation     = *( NOT / "-" ) primary
primary      = "(" disjunction ")" / term
term         = phrase / field-term / text
field-term   = field ":" ( phrase / value )
field        = 1*%x61-7A                 ; a name of §8's table, as written
value        = 1*vchar / 2*vchar "*"     ; may hold ":"
text         = 1*tchar / 2*tchar "*"     ; holds no ":"
phrase       = DQUOTE *pchar DQUOTE
OR           = %i"or"
AND          = %i"and"
NOT          = %i"not"
sep          = 1*( SP / HTAB / CR / LF ) ; separates tokens, is none
vchar        = %x0-8 / %xB-C / %xE-1F / %x21 / %x23-27 / %x2B-D7FF / %xE000-10FFFF
tchar        = %x0-8 / %xB-C / %xE-1F / %x21 / %x23-27 / %x2B-39 / %x3B-D7FF / %xE000-10FFFF
pchar        = %x0-21 / %x23-D7FF / %xE000-10FFFF

kind-value   = %s"mail" / %s"contact" / %s"event" / %s"task" / %s"journal" / %s"file"
is-value     = %s"unread" / %s"read" / %s"flagged" / %s"answered" / %s"draft" / %s"encrypted"
has-value    = %s"body" / %s"attachment" / %s"phone" / %s"address" / %s"birthday" / %s"photo"
status-value = %s"needs-action" / %s"in-process" / %s"completed" / %s"cancelled"
priority-value = %s"high" / %s"medium" / %s"low" / %s"none"
date-value   = point / point ".." [ point ] / ".." point
point        = year / month / day / %s"today" / %s"yesterday" / relative
year         = 4DIGIT
month        = 4DIGIT "-" 2DIGIT            ; 01 to 12
day          = 4DIGIT "-" 2DIGIT "-" 2DIGIT ; a date of the Gregorian calendar
relative     = 1*DIGIT ( %s"d" / %s"w" / %s"y" )
stamp-value  = stamp / stamp ".." [ stamp ] / ".." stamp
stamp        = 1*DIGIT
```

- **Tokens** are `(`, `)`, a phrase, a field term, a text, an operator and a `-` beginning a primary, read longest first: a text, a field term and a value run to the next `sep`, parenthesis or double quote. A `sep` is no token and is otherwise insignificant, so two words are two terms only across one, while a parenthesis or a phrase needs none beside it.
- **Operators.** A text spelling `and`, `or` or `not`, in any case, is the operator, never a term; to search the word, quote it.
- **Negation.** A `-` at the start of a primary (at the query's start, after whitespace, after `(`, or after another `-` or `not`) is `not`, never inside a word: `stand-up` is one text and `from:-x` a value, while `-"weekly sync"`, `-(a or b)`, `-from:x` and `--x` negate. To search a word starting with `-`, quote it.
- **Precedence.** `not` binds tighter than `and`, explicit or by juxtaposition, which binds tighter than `or`; parentheses group.
- **Fields.** A word holding a colon outside quotes is a field term, never free text. Its field is the text before the first colon and MUST be a name of §8's table, as written; anything else is refused (`unknown-field`). To search a text holding a colon, a URL or a time, quote it. The value is the rest of the word, colons included, or the phrase right after the colon.
- **Phrases** run to the next `"`, with no escape. Nothing inside one is an operator, a field or a wildcard: its text is tokenised as §5 says and matched as a phrase (§8.5). A text or a phrase yielding no token matches no item.
- **Wildcard.** A `*` MUST be the last character of a text or of a text field's value, after two characters or more. Anywhere else outside a phrase it is refused (`invalid-wildcard`). The text fields are `subject:`, `title:`, `summary:`, `body:`, the role fields, `with:`, `person:`, `attachment:`, `mimetype:` and `location:`; a value holding `@` is an address, not text.
- **Values.** `kind:`, `is:`, `has:`, `status:` and `priority:` take `kind-value`, `is-value`, `has-value`, `status-value` and `priority-value`; `date:` and `when:` take `date-value`, `changed:` `stamp-value`; every other field takes its value as written. A phrase value is read the same, its quotes aside.
- **Limits.** A query is bounded, so every client refuses the same hostile one before reading it whole:

| Limit | Bound | Span refused (§8.4) |
| --- | --- | --- |
| length | 1,024 Unicode scalar values | from the first value past the bound to the end |
| nesting | 32 groups open at once | the `(` opening the 33rd |
| terms | 128 terms, a `term` of the grammar each | the 129th term |

### 8.4 Refusals

A query the grammar does not accept, or whose field or value §8.3 does not know, MUST be refused whole, never answered in part nor read as free text. The refusal is this JSON object, with these keys:

| Key | Value |
| --- | --- |
| `code` | one of the codes below |
| `message` | a sentence for a person; informative |
| `start`, `end` | the span at fault, half-open offsets into the query in Unicode scalar values |
| `expected` | what would have been valid at `start` (field names, values, `)`, a term), possibly empty |
| `fields` | every field name of §8's table, without its colon, always for `unknown-field`, possibly empty otherwise |

| `code` | Fault | Span |
| --- | --- | --- |
| `empty-query` | no term in the query, or in a group | the query, or the group with its parentheses |
| `unterminated-phrase` | a `"` with no closing one | from that quote to the end |
| `unbalanced-parenthesis` | a `)` with no `(`, or a `(` never closed | that parenthesis |
| `dangling-operator` | an `and` or `or` missing a side, a `not` with nothing after it, a `-` followed by whitespace, a `)` or the end | the `-` so followed, else the `and` or `or` missing its side, else the first `not` or `-` of the run missing its term |
| `unknown-field` | a field that is not in §8's table | the field and its colon |
| `invalid-value` | an empty value, a value out of `kind-value`, `is-value`, `has-value`, `status-value` or `priority-value`, a `changed:` value no `stamp-value` reads | the value, or the term when the value is empty |
| `invalid-date` | a `date:` or `when:` value no `date-value` reads | the value |
| `invalid-wildcard` | a `*` §8.3 does not accept | the first `*` of the text or value |
| `limit-exceeded` | a query past a limit of §8.3 | as §8.3's table says |

A query with several faults answers one, found in four passes: the length, the phrases, the parentheses with their nesting, then the terms and operators in reading order, their count among them. The first pass to find a fault answers its leftmost: a query past the length is refused whatever else it holds, and an unbalanced parenthesis left of the one opening the 33rd group answers first.

A term is checked for its count, then its field, then an empty value, then the wildcard, then its value. A value's span includes a phrase's quotes.

### 8.5 Text terms

A text, a phrase and the value of a text field holding no `@` (§8.3) are each a **text term**, matched on the index's tokens, so every shape answers one hit set:

- Its text, a phrase's between its quotes and a value's without its trailing wildcard, is folded as §5 says and split into tokens by the index's tokenizer, which splits the indexed text alike.
- It matches a field holding those tokens consecutively and in that order, one token anywhere in the field; a term ending with the wildcard reads its last token as the prefix of one.
- No character of the term is syntax of the full-text engine: a character the tokenizer keeps in no token only separates tokens, whatever the engine makes of it in an expression of its own (FTS5's `^`, `+`, `{`, `:`, a `*` inside a phrase, `NEAR`, `AND`, `OR`, `NOT`), and a word is a token in any case.
- A term yielding no token matches no item.
- Free text matches in every field of §6, a field term in the field §8's table maps it to and in no other: `subject:`, `title:`, `summary:` and `person:` the `title` field, `body:` the `body` field, a role field its own, `with:` the `people` field, `attachment:` and `mimetype:` the `attachment` field, `location:` the `place` field. A bodiless placement matches on its summary's fields (§6) alone.

The canonical shape compiles a text term to one FTS5 expression, bound as `:match` to `match_objects` and `match_summaries` and to their page and probe forms (§8.2):

- one FTS5 string: `"`, the folded text with every `"` doubled, then `"`, which FTS5 hands whole to the tokenizer as a phrase;
- then ` *` when the term ends with the wildcard, and nothing else;
- before it, for a field term, the column filter `{`, its field's column, `} : `, among `object_text`'s columns for a body and `summary_text`'s for a summary; free text takes none. A field term whose field `summary_text` lacks (`body:`, `attachment:`, `mimetype:`, `location:`) is not run against summaries.

Nothing else of the query reaches the expression. For example `body:^report` compiles to `{body} : "^report"`, matching a body holding `report` anywhere, where `{body} : ^report` would match one beginning with it.

## 9. Threads

Mail only. A message's `parent` is its first `In-Reply-To` id, else the last `References` id (RFC 5322 §3.6.4), from the headers at `Full` and from its first `mail_in_reply_to` id (`position` 0) for a bodiless item.

A **member** is a message a live mail placement holds. Every id a member bears or names as its parent has a `message` row, present in the store or not, and no other id has one. Two replies to a parent nobody holds are thus one thread, and a parent arriving later joins what already waited for it. A cycle is broken by ignoring the edge that would close it.

A thread is the connected set over those rows. Its id is the link id of the present member with the lowest `(sort_key, link_id)`, recomputed when threads join: the new row is written and the members repointed before the old row goes, since the old row's delete cascades. No joining by subject.

**A message that leaves prunes its thread.** When a mail placement goes (a deleted row, or the key reconciliation, §4) and no other holds its link id, the rows become those a rebuild from the store as it stands writes, in the same transaction: within its thread, a row no member holds names no parent (`unparent_messages`), then a row no member holds and no row names goes (`prune_messages`). The rows left are re-keyed: each connected set among them is a thread named by its member with the lowest `(sort_key, link_id)` (`thread_rows`), written and its rows repointed before a thread row no row points to goes (`delete_thread`). A purged message thus leaves no id, parent nor thread of its own in the index, and stays only as the phantom parent a member names.

`thread:` returns the present members in the query's account (`thread_of` names a message's thread, `thread_members` lists it). A threaded listing collapses hits to threads with count, first and last date.

## 10. Tags

A tag is a flag of the placement (`placement_flag`, STORAGE §13), so it syncs with the sources that carry keywords.

Tagging from a query stages one `set-flags` action per placement of each hit through the queue (STORAGE §15), as a producer. The `flag` table is rebuilt from the feed and holds no state of its own.

## 11. Test vectors

vectors/search/ holds the fixture store and the queries every conforming implementation MUST answer alike, each file stating the version of its format, `v` 2 for queries.json and `v` 1 for the other two, and conforming to its JSON Schema under vectors/schema/:

- `store.json`: collections (`id`, `account`, `kind`), items (`collection`, `seq`, `link_id`, `flags`, and a `fixture` or a `summary` for a bodiless item) and the references the store records (`from_kind`, `from_link_id`, `to_kind`, `to_link_id`, `role`, `origin`), given rather than derived.
- `queries.json`: the `now` relative dates resolve against, in UTC, the horizon and the coverage, and the cases, then the `occurrences` windows, each a `start`, an `end` and the `rows` `occurrences_between` answers for it, `(collection, seq, start, end)` in its order.
- `chunks.json`: field texts and the chunk boundaries §6 cuts them into.

A case has a `query`, an optional `sort` (`date`, `name`, `relevance`), and one answer:

- the expected `hits` as `(account, seq)` pairs, a list when the case says `ordered` and a set otherwise;
- or the `threads` of a threaded listing (§9), each its id, `count`, `first`, `last` and hits;
- or the `error` of a refusal, its `code`, `start` and `end` compared and the rest not.

A case whose date range leaves the horizon says `horizon_left`. A case stating `cut` compares the count `cut_before` answers over its collections and its range (§8.2). A case stating `temporal`, `"full"` or its `since`, `until` and `filling`, compares the temporal coverage, which the collections' `sources` rows in store.json (`source`, `covered_since`, `covered_until`, `covered_at`) give. A case not stating it compares nothing there.

An implementation builds the store, indexes it at `now` stating no zone, so `UTC` (§7), and compares.

The cases bind every shape (§2), but a case sorted by `relevance` binds its order only where the shape ranks by bm25: another compares its hits as a set, and one refusing `relevance` skips it. The fold and the tokenisation are pinned by cases whose hits depend on diacritics (a Latin accent, a Greek tonos), a domain token or a digits-only telephone number, §8.5's compilation by text terms holding FTS5's syntax, §8.3's limits by a query at and one past each, and §7's bounds by a series stepping by the hour and one by the second.

checks/vectors.py validates that every fixture and placement resolves, re-derives every refusal, the limits of §8.3 read from its table, and every chunk boundary from §8.3, §8.4 and §6, and checks that every other query is one the grammar accepts, and that every occurrence row names a calendar item and overlaps its window in order. It also re-derives the hits of every case whose query is one text term on the `title` field, compiling it as §8.5 says over an FTS5 table of the fixtures' titles, and refuses a case holding an FTS5 metacharacter that the term's text spliced raw would answer alike; and it expands the series a simple rule states (a UTC start, a fixed step, limiting `BYxxx` parts), so the windows and the `cut` counts reaching them follow §7's bounds. Only an implementation runs a case against the store.

## 12. Conformance

An implementation offering search conforms by one profile or both, stated as STORAGE §17 says with the shape it builds or reads (`search-draft-08 indexer (canonical)`, `search-draft-08 query client (canonical)`), and MUST meet every section its row names and answer the vectors it names.

| Profile | What it does | Owes | Vectors |
| --- | --- | --- | --- |
| indexer | a store reader (STORAGE §17) writing index.db under index.lock | §2 to §7, §9 | store.json indexed, every case of queries.json answered on its index by a conforming query client; chunks.json |
| query client | reads index.db, the store attached | §2's refusal, §5, §8, §9, §10, a tag enqueued as a STORAGE producer | every case of queries.json its shape binds (§11), on an index a conforming indexer built from store.json |

Both meet STORAGE §18, index.db holding the text of every body indexed, and an indexer erases as §4 says.
