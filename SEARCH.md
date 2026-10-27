# Pimdir search specification

Status: draft-04

The search part of the pimdir standard: a full-text index over a store ([STORAGE.md](./STORAGE.md)) and the query language over it, cross-domain from the first line. A query names people, dates, tags, kinds and text and answers with items of every kind: a person's card, the mail they sent and the meetings they attend are one result set.

An implementation MAY omit search; one that offers it MUST conform, so every client on one store answers `is:unread from:jane` the same way, vectors/search/ being the bar. The index presupposes the store: it is built from the store's rows and bodies, and rebuilt at will.

[OVERVIEW.md](./OVERVIEW.md) §10 explains the model; [GUIDE.md](./GUIDE.md) §15 runs the refresh and the query as procedures. Both are informative and this part wins on any disagreement.

The key words MUST, MUST NOT, SHOULD, SHOULD NOT and MAY are to be interpreted as in RFC 2119. §n of STORAGE.md is written STORAGE §n.

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

## 1. Scope

The store answers the structured questions itself: a sender, a date range, a name, a flag, everything about an address (STORAGE §14.1, Annex A.6). The index adds the three it cannot: text, calendar time across a recurring series, threads.

A query composes both: a structured predicate is a seek on the store, a text predicate a match on the index, and the result is their intersection in the store's own order.

The index is derived. Every row is recomputed from the store and the bodies, and dropping index.db loses nothing.

## 2. Requirements

- The index MUST be a SQLite database named index.db in the store directory (STORAGE §3), every table `STRICT`, `PRAGMA foreign_keys = ON`, `PRAGMA journal_mode = WAL` RECOMMENDED so query clients read while a refresh writes.
- Implementations MUST require **SQLite ≥ 3.43** with FTS5, for `contentless_delete`. This floor is the index's alone.
- The schema is [migrations/search/0001_init.sql](./migrations/search/0001_init.sql), its version in the index's own `PRAGMA user_version`, mirrored in `index_meta.version`. An index at another version, or whose `index_meta.tokenizer` differs from §5's, MUST be rebuilt: there are no index migrations.
- The statements are under [queries/search/](./queries/search/), one file per statement named after it, prepared with the store attached read-only as `store`.

## 3. The index

The **indexer** is a store reader (STORAGE §8): read-only on pimdir.db, no store lock, running whether or not an owner syncs. It is the sole writer of index.db and MUST hold an exclusive advisory lock on index.lock for a refresh, on the owner lock's terms. **Query clients** open index.db read-only, any number at once, no lock.

The main database is index.db, pimdir.db attached as `store` through a read-only URI, so one statement joins both (`hit`, `coverage`).

Tagging is a store write through the queue (§10). Nothing writes the store through the index. References (STORAGE §14.2) are read from the store by `linked`, never copied into the index.

The index holds one `object` row and one `object_text` FTS row per indexed body, keyed on the store's hash, so a body filed in three collections is tokenised once; one `placement` row per live item seen; a `summary_text` row per placement with no body; the derived `flag`, `occurrence`, `thread`, `message` and `chunk` tables; and `index_meta`, the store cursor folded in (§4) and the horizon (§7).

## 4. Refresh

A refresh folds the change feed (STORAGE §4.5): every item stamped above `index_meta.store_change`, the last stamp drawn when the previous pass began, in stamp order, in read transactions of bounded size so the store's WAL still checkpoints.

Per row: the body is indexed if its hash is new (§6); the placement is upserted; summary text is written while it has no body and dropped when it gains one; flags are replaced; occurrences are re-expanded when the body changed (§7); the thread is updated (§9). A deleted row loses its placement, which takes its flags and occurrences by cascade and whose summary text the indexer deletes by the rowid the delete returns; its body's text stays until the object goes. A body the blob directory no longer holds when the indexer opens it is not `unparseable`: no `object` row is written and the row is met again on the next pass.

When `store_meta.purges` moved, which counts purged items and collected objects alike, or a collection stamp did (a rename restamps the items under the new id and leaves the old placements to this pass), the indexer reconciles keys: `placements_gone` and `objects_gone` name what the store no longer holds. The cursor read before the pass is written by `set_index_cursor` in the transaction completing it, so a crash replays and skips nothing. A batch MAY record its last row's stamp (`load_changed_items` answers each row's) as `store_change` in its own transaction, the purge count left as the previous pass recorded it, so a crash resumes after the last batch committed and still reconciles.

A store from before the feed carries stamps of `0` and is indexed whole once. Extraction MAY run in parallel; the index is written by one transaction per batch.

## 5. Tokens

The tokenizer is `unicode61 remove_diacritics 2`, no stemming, `prefix = '2 3'` for the trailing wildcard (§8), recorded in `index_meta.tokenizer`. No stemming because FTS5's only stemmer is English-only; no trigram substring search because it triples the index for a feature the target audience's tools lack.

An address is indexed whole, as its local part and as its domain in the `people` field, so `alice`, `example.org` and `alice@example.org` all match and `from:@example.org` is a match rather than a scan. A telephone number is indexed as its digits alone beside the value.

## 6. Extraction

A body is extracted once, by hash, into seven fields: `title`, `people` (every name and address, plus §5's address tokens), `body`, `attachment` (part names and media types), `place`, `org`, `note`; and, beside `people`, one field per address role of STORAGE Annex A.6 (`from`, `to`, `cc`, `bcc`, `email`, `organizer`, `attendee`) holding that role's names and addresses alone, so `from:jane` is a match on the sender and not on anyone the message names.

| Kind | `title` | `people` | `body` | `attachment` | `place` | `org` | `note` |
| --- | --- | --- | --- | --- | --- | --- | --- |
| mail | `Subject` | `From`, `To`, `Cc`, `Bcc` | the text parts | its attachments' names and media types (STORAGE §14.3) | | | |
| contact | `FN`, `N` components, `NICKNAME` | every `EMAIL`, the `FN` | | | `ADR` | `ORG`, `TITLE`, `ROLE` | `NOTE`, every `TEL` |
| calendar | `SUMMARY` | `ORGANIZER`, `ATTENDEE` values and `CN`s | `DESCRIPTION` | `ATTACH` names | `LOCATION` | | `COMMENT` |

Mail extraction MUST walk the MIME tree, decode transfer encodings, transcode charsets, decode RFC 2047 and RFC 2231, prefer `text/plain` and reduce `text/html` to text. Attachment content is out of scope.

A `multipart/encrypted` or `application/pkcs7-mime` body is recorded `encrypted`, headers indexed and body not; indexing decrypted content is an opt-in that writes plaintext into index.db and MUST be documented as such. A body no parser accepts is `unparseable`, with what could be read.

Extraction MUST record the chunk boundaries of the `body` and `note` fields, one `chunk` row per chunk (`insert_chunk`), numbered from 0 in text order, the `body` field's before the `note` field's, and bounded by UTF-8 byte offsets into the field's text. A field's text is split into paragraphs at every blank-line run: a line break (LF, or CR LF) followed by one or more lines holding nothing but spaces and tabs, each ended by a line break. Paragraphs are packed greedily, in order, into chunks of at most 1024 bytes, a chunk running from its first paragraph's start to its last one's end, the runs between them included; a paragraph that does not fit the chunk being filled starts the next one. A paragraph longer than 1024 bytes is cut into pieces, each ending just after the last space, tab, CR or LF within its first 1024 bytes, else at the last character boundary within them; every piece but the last is a chunk of its own, and the last is packed as a paragraph. The chunks thus cover the text but its blank-line runs, a field of blank lines alone having none. A snippet is cut from a hit's chunks (`chunks_of`), and an embedding index embeds the same ones without extracting again. Other fields are short and not chunked; a summary row has no chunk.

A placement with no body indexes its summary row and address rows into `summary_text`: `title` from the subject, `fn`, `summary` or a file's `name`, `people` and the role fields from the addresses. That keeps a headers-only replica searchable, and it is dropped once the body is indexed. A file (STORAGE §14.3) is indexed from its summary alone, its body or not: its content is out of scope, as attachment content is. Every value is decoded on Annex A.0's terms.

## 7. Calendar time

`sort_key` holds a series' first occurrence (STORAGE Annex A.3), so `date:today` cannot be answered from the store for a meeting that started years ago. The index materialises every occurrence within a **horizon**, default one year back and two forward, into `occurrence(start, end)` as instants, using the resource's `VTIMEZONE`s, `RDATE`, `EXDATE` and `RECURRENCE-ID` overrides.

An event spans `DTSTART` to `DTEND` or `DURATION`, and with neither one day for a date and no time for a date-time (RFC 5545 §3.6.1); a task to its `DUE`, a task with a `DUE`, no `DTSTART` and no `RRULE` being one zero-length occurrence at its due time; a journal its `DTSTART` alone. A zoned time resolves through the resource's own `VTIMEZONE`, else a time zone database by `TZID`, else as floating, the same order as STORAGE Annex A.3, and here the answer moves hits across a day boundary rather than a sort position. A floating time and a date are read in the time zone the indexer states, UTC when it states none, as §8.1 reads a query's dates. A resource holding overrides and no master, as an attendee invited to a single instance stores it, yields each override as an occurrence, spanning its own `DTSTART` to its end by the rules above. A series no expander accepts (an `RRULE` with no `DTSTART`) yields no occurrence and MUST NOT fail the pass, and an implementation SHOULD bound the occurrences one item may write.

An item is re-expanded when its body changes, when the horizon rolls and when the time zone database changes version. The roll re-expands the recurring items whose `until` is absent or not before the old horizon's end, and expands the single items whose start the new window covers and the old one did not (`items_to_reexpand`, bound to both horizons before `set_horizon` records the new one). A query outside the horizon MUST say so in its coverage (§8).

A zoned time resolved through the time zone database moves when the database does. `index_meta.tzdb_version` records the version the occurrences were expanded under, as the database names its release (IANA's `2026b`), empty with none. An indexer whose database names another version MUST re-expand every live calendar item and record the new version (`set_tzdb_version`) in the pass that sees it: `items_to_reexpand`, bound to that version, returns every live calendar item when it is not the recorded one, the horizon bound twice when it did not roll.

## 8. The query language

A query is whitespace-separated terms, implicitly conjoined, with `or`, `not`, parentheses and quoted phrases; a term is free text or `field:value`; a trailing `*` is a prefix wildcard. Free text matches every field of §6. §8.3 is the grammar and §8.4 the answer to a query it refuses. FTS5's own syntax is never accepted raw.

| Field | Meaning |
| --- | --- |
| `subject:` `title:` `summary:` | the `title` field |
| `body:` | the `body` field |
| `from:` `to:` `cc:` `bcc:` `attendee:` `organizer:` `email:` | the role's `item_address` seek for a value containing `@` (a bare `@domain` seeks the domain), the role's own field otherwise |
| `with:` | any role, the same way over the `people` field |
| `person:` | contacts whose `title` matches, expanded to `with:` over their `email` rows |
| `tag:` `flag:` | a store flag (§10), as written |
| `is:` | `unread` the absence of `\Seen`; `read`, `flagged`, `answered`, `draft` the presence of `\Seen`, `\Flagged`, `\Answered`, `\Draft`; `encrypted` the extraction status (§6) |
| `has:body` `has:attachment` | a stored body; `mail_summary.attachment` = 1 or a non-empty `attachment` field |
| `kind:` | `mail`, `contact`, `event`, `task`, `journal`, `file` |
| `account:` `collection:` `folder:` | the store's axes, `folder:` an alias |
| `date:` `when:` | an instant or a range (§8.1) |
| `thread:` `id:` | a thread id (§9); a link id or a `seq` |
| `linked:` | the items at the other end of the named item's references, either direction (`linked`): `linked:<id>`, or `linked:<role>:<id>` for one role of STORAGE §14.2, the item named as `id:` names it, with every kind it is held under |
| `attachment:` `mimetype:` | the `attachment` field |
| `location:` | the `place` field |
| `changed:` | change stamps over `items.changed` (STORAGE §4.5), a stamp or a range, both ends included |

### 8.1 Dates

A `date:` or `when:` value is a point or a range of points (`date-value`, §8.3). A year, a month, a day, `today` and `yesterday` each cover their calendar span, in the time zone the client states, UTC when it states none; a relative amount (`3d`, `2w`, `1y`: days, weeks of seven days, calendar years) names the instant that long before `now`. A single point is its span, a single relative amount the span from its instant to `now`. A range `a..b` runs from the start of `a`'s span to the end of `b`'s, either side open. Every span is half-open. Mail compares `sort_key`; an event, task or journal compares occurrences (§7), an occurrence overlapping a half-open range when it starts before the range ends and ends after the range starts, a zero-length one when it starts inside it; a contact or a file has no date, a file's `sort_key` being its name, and is excluded from a date-bounded query unless `kind:contact` or `kind:file` names it. A range leaves the horizon when it starts before the horizon's start or ends after its end, an open side always.

### 8.2 Semantics

- **A hit is `(account, seq)`**, one per item per account, carrying its placements (STORAGE §9.2). An implementation MAY flatten to one row per placement on request.
- **Tags** are per placement in the store and per hit in the query: `tag:x` matches when any placement carries `x`, `not tag:x` when none does.
- **Order** is `sort_key` descending by default, the undated last (contacts and files) in their own `sort_key` ascending; `name` the item's title (a message's subject, a card's `fn`, a calendar component's summary, a file's name) folded as Annex A.2 folds `fn`, ascending, a title-less item first; `relevance` by FTS5 `bm25`, best first. Ties go to `seq`, then the account.
- **Deleted items are excluded.** The trash is the store's (STORAGE §11), not the index's.
- **Coverage is part of the answer**: how many live items have no body among the kinds whose body search reads, mail, contacts and calendars, never files, which §6 indexes from their summary alone (`coverage`, per kind, which a client narrows to the query's collections), whether a date range left the horizon (§8.1), and per hit whether it matched on its body or its summary.
- **Coverage has a temporal axis**: whether the store holds every member of the queried collections over the query's date range, open on a side the query does not bound, read from their sources' coverage (STORAGE §10, `list_coverage`). It is `full`, or `bounded` with `since`, the instant below which a queried collection is not known complete (a `covered_since` above the range's start, `null` when no floor is the cause), `until`, the instant from which one is not (a `covered_until` below the range's end, `null` likewise), and `filling`, true when a source of a queried collection never closed a round, so nothing there is known complete. A collection no source syncs is complete. The collections' answers roll up conservatively: the highest `since`, the lowest `until`, `filling` when any is.
- A snippet is re-read from the blob for the hits shown, from their chunks (§6).

### 8.3 Grammar

The query is a string of Unicode scalar values, read under this ABNF (RFC 5234, with RFC 7405's `%s` for a case-sensitive string and `%i` for an insensitive one):

```abnf
query        = ws [ disjunction ws ]
disjunction  = conjunction *( ws OR ws conjunction )
conjunction  = negation *( ws [ AND ws ] negation )
negation     = *( NOT ws / "-" ) primary
primary      = "(" ws disjunction ws ")" / term
term         = phrase / field-term / text
field-term   = field ":" ( phrase / value )
field        = 1*%x61-7A                 ; a name of §8's table, as written
value        = 1*vchar / 2*vchar "*"     ; may hold ":"
text         = 1*tchar / 2*tchar "*"     ; holds no ":"
phrase       = DQUOTE *pchar DQUOTE
OR           = %i"or"
AND          = %i"and"
NOT          = %i"not"
ws           = *( SP / HTAB / CR / LF )
vchar        = %x0-8 / %xB-C / %xE-1F / %x21 / %x23-27 / %x2B-D7FF / %xE000-10FFFF
tchar        = %x0-8 / %xB-C / %xE-1F / %x21 / %x23-27 / %x2B-39 / %x3B-D7FF / %xE000-10FFFF
pchar        = %x0-21 / %x23-D7FF / %xE000-10FFFF

kind-value   = %s"mail" / %s"contact" / %s"event" / %s"task" / %s"journal" / %s"file"
is-value     = %s"unread" / %s"read" / %s"flagged" / %s"answered" / %s"draft" / %s"encrypted"
has-value    = %s"body" / %s"attachment"
date-value   = point / point ".." [ point ] / ".." point
point        = year / month / day / %s"today" / %s"yesterday" / relative
year         = 4DIGIT
month        = 4DIGIT "-" 2DIGIT            ; 01 to 12
day          = 4DIGIT "-" 2DIGIT "-" 2DIGIT ; a date of the Gregorian calendar
relative     = 1*DIGIT ( %s"d" / %s"w" / %s"y" )
stamp-value  = stamp / stamp ".." [ stamp ] / ".." stamp
stamp        = 1*DIGIT
```

- **Tokens** are read longest first: a text, a field term and a value run to the next whitespace, parenthesis or double quote, so terms are juxtaposed across whitespace, a parenthesis or a quote, and `ws` is otherwise insignificant.
- **Operators.** A text spelling `and`, `or` or `not`, in any case, is the operator, never a term; to search the word, quote it. A `-` at the start of a primary (at the query's start, after whitespace, after `(`, or after another `-` or `not`) is `not`, never inside a word: `stand-up` is one text and `from:-x` a value, while `-"weekly sync"`, `-(a or b)`, `-from:x` and `--x` negate; to search a word starting with `-`, quote it. `not` binds tighter than `and`, explicit or by juxtaposition, which binds tighter than `or`; parentheses group.
- **Fields.** A word holding a colon outside quotes is a field term, never free text: its field is the text before the first colon and MUST be a name of §8's table, as written; anything else is refused (`unknown-field`). To search a text holding a colon, a URL or a time, quote it. The value is the rest of the word, colons included, or the phrase right after the colon.
- **Phrases** run to the next `"`, with no escape. Nothing inside one is an operator, a field or a wildcard: its text is tokenised as §5 says and matched as a phrase. A text or a phrase yielding no token matches no item.
- **Wildcard.** A `*` MUST be the last character of a text or of a text field's value, after two characters or more, the text fields being `subject:`, `title:`, `summary:`, `body:`, the role fields, `with:`, `person:`, `attachment:`, `mimetype:` and `location:`, and a value holding `@` being an address and not text. Anywhere else outside a phrase it is refused (`invalid-wildcard`).
- **Values.** `kind:`, `is:` and `has:` take `kind-value`, `is-value` and `has-value`; `date:` and `when:` take `date-value`, `changed:` `stamp-value`; every other field takes its value as written. A phrase value is read the same, its quotes aside.

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
| `invalid-value` | an empty value, a value out of `kind-value`, `is-value` or `has-value`, a `changed:` value no `stamp-value` reads | the value, or the term when the value is empty |
| `invalid-date` | a `date:` or `when:` value no `date-value` reads | the value |
| `invalid-wildcard` | a `*` §8.3 does not accept | the first `*` of the text or value |

A query with several faults answers one, found in three passes: the phrases, the parentheses, then the terms and operators in reading order; the first pass to find a fault answers its leftmost. A term is checked for its field, then an empty value, then the wildcard, then its value. A value's span includes a phrase's quotes.

## 9. Threads

Mail only. A message's `parent` is its first `In-Reply-To` id, else the last `References` id (RFC 5322 §3.6.4), from the headers at `Full` and from `mail_summary.in_reply_to` for a bodiless item. Every id a member names has a `message` row, present in the store or not, so two replies to a parent nobody holds are one thread and a parent arriving later joins what already waited for it; a cycle is broken by ignoring the edge that would close it. A thread is the connected set over those rows; its id is the link id of the present member with the lowest `(sort_key, link_id)`, recomputed when threads join, the new row written and the members repointed before the old row goes, since the old row's delete cascades. No joining by subject.

`thread:` returns the present members in the query's account (`thread_of` names a message's thread, `thread_members` lists it); a threaded listing collapses hits to threads with count, first and last date.

## 10. Tags

A tag is an `items.flags` entry, so it syncs with the sources that carry keywords and needs no dump and restore. Tagging from a query stages one `set-flags` action per placement of each hit through the queue (STORAGE §15), as a producer. The `flag` table is rebuilt from the feed and holds no state of its own.

## 11. Test vectors

vectors/search/ holds the fixture store and the queries every conforming implementation MUST answer alike:

`store.json`, collections (`id`, `account`, `kind`), items (`collection`, `seq`, `link_id`, `flags`, and a `fixture` or a `summary` for a bodiless item) and the references the store records (`from_kind`, `from_link_id`, `to_kind`, `to_link_id`, `role`, `origin`), given rather than derived; `queries.json`, the `now` relative dates resolve against, in UTC, the horizon and the coverage, and cases with a `query`, an optional `sort` (`date`, `name`, `relevance`), and one answer: the expected `hits` as `(account, seq)` pairs, a list when the case says `ordered` and a set otherwise; or the `threads` of a threaded listing (§9), each its id, `count`, `first`, `last` and hits; or the `error` of a refusal, its `code`, `start` and `end` compared and the rest not. A case whose date range leaves the horizon says `horizon_left`; a case stating `temporal`, `"full"` or its `since`, `until` and `filling`, compares the temporal coverage, which the collections' `sources` rows in store.json (`source`, `covered_since`, `covered_until`, `covered_at`) give, and a case not stating it compares nothing there. `chunks.json`, field texts and the chunk boundaries §6 cuts them into.

An implementation builds the store, indexes it at `now`, and compares. checks/vectors.py validates that every fixture and placement resolves, re-derives every refusal and every chunk boundary from §8.3, §8.4 and §6, and checks that every other query is one the grammar accepts; only an implementation runs a case against the store. Tokenisation is pinned by cases whose hits depend on diacritics, a domain token or a digits-only telephone number.
