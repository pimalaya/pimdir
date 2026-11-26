# Pimdir search specification

Status: search-v1.0.0, requiring storage-v1.0.0, released together with the storage and sync parts

The search part of the pimdir standard: a full-text index over a store ([STORAGE.md](./STORAGE.md)) and the query language over it, cross-domain.

A query names people, dates, tags, kinds and text, and answers with items of every kind: a person's card, the mail they sent and the meetings they attend are one result set.

An implementation MAY omit search. One that offers it MUST conform by a profile of §12, vectors/search/ being the bar, so every client on one store answers `is:unread from:jane` the same way.

This part binds what an index answers, not how it holds it: the index's tables, its statements and how a refresh writes them are its implementation's own, io-pimdir's for the reference implementation.

[OVERVIEW.md](./OVERVIEW.md) §10 explains the model. It is informative and this part wins on any disagreement.

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in BCP 14 (RFC 2119, RFC 8174) when, and only when, they appear in all capitals, as shown here. Every statement of behaviour in this part is normative: a key word marks its requirement level, and a statement carrying none binds as one carrying MUST. Notes, examples and rationale are informative and marked as such: a paragraph opening with *Note:*, an instance of what a sentence states given in parentheses or after "for example", and a reason given with "so", "since" or "because", none of which adds a requirement. §n of STORAGE.md is written STORAGE §n.

## Contents

1. [Scope](#1-scope)
2. [The index file](#2-the-index-file)
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

The store answers the structured questions itself: a sender, a date range, a name, a system flag (§8), everything about an address (STORAGE §14.1, Annex A.6). The index adds what it cannot: text, calendar time across a recurring series, threads, and what a card holds.

A query composes both: a structured predicate is a seek on the store, a text predicate a match on the index, and the result is their intersection in the store's own order.

The index is derived. Every row is recomputed from the store and the bodies, and dropping index.db loses nothing. An index is rebuilt, never migrated.

## 2. The index file

Two implementations sharing one store directory share these rules of its index:

- **A SQLite file.** The index MUST be a SQLite database named index.db, at the path STORAGE §3 reserves.
- **An index names its version and its shape.** Whatever its layout, an index holds a one-row table `index_meta` whose `format` is `pimdir-index`, whose `format_version` names the version of this part it follows, `search-vN`, N its major alone (`search-v1` for this version), a draft's index naming its draft (`search-draft-NN`), and whose `shape` names the layout of its tables, a name no other layout bears (io-pimdir's is `canonical`). Versions are ordered: drafts by their number, every draft below every release, releases by their major.
- **An indexer leaves an index that is not its own untouched.** An indexer MUST refuse an index.db holding no `index_meta`, one whose `shape` is not its own, and one whose `format_version` lies above its own, naming the index's version and shape and its own, and MUST NOT rebuild, write nor delete it: a person deleting index.db hands the store to another indexer, losing nothing (§1).
- **A query client reads only an index it implements.** It MUST refuse an index whose `shape` or `format_version` it does not implement, naming both, rather than answer from it; it implements no draft, as STORAGE §4.2 has no release open a draft's store.
- **One writer.** The indexer is the sole writer of index.db and MUST hold an exclusive advisory lock on index.lock for a refresh, on the owner lock's terms: taken whole-file with `flock(2)` on Unix or `LockFileEx` on Windows, never an `fcntl` record lock (STORAGE §8). Query clients open index.db read-only, any number at once, and take no lock.

## 3. The index

The **indexer** is a store reader (STORAGE §8): read-only on pimdir.db, no store lock, running whether or not an owner syncs. A **query client** reads index.db with the store beside it. An index derives from the store and the bodies:

- the text of each body, extracted once by its hash (§6), so a body filed in three collections is tokenised once;
- per live placement, its **document**: the body it names or, while it names none, its own summary (§6), never both;
- the keywords of each placement, its flags but the five system flags (§10);
- the occurrences of each calendar item, and where they were cut (§7);
- the threads of the mail (§9).

It holds no system flag (`\Seen`, `\Answered`, `\Flagged`, `\Draft`, `\Deleted`, each by its exact bytes), no label nor property (STORAGE §4.3), no reference (STORAGE §14.2) and no deleted item (STORAGE §11): a query reads those from the store (§8). Nothing writes the store through the index.

## 4. Refresh

A refresh folds the change feed (STORAGE §4.5) in stamp order, in read transactions of bounded size so the store's WAL still checkpoints.

**A refreshed index is a rebuilt one.** Once a refresh completes, the index answers every query as one built from the store as it then stands, whatever the writes (an insert, a flag, a body or a summary replaced, a rename, a retained, purged or erased item). A refresh cut short, by a deadline or a crash, is resumed by the next, which skips nothing. An index built from another store or another incarnation of it, or having folded a stamp the store has not drawn, is a reset (STORAGE §4.5), and is rebuilt.

Between two refreshes the index lags the store: an answer states the lag (§8.2), which a client relies on rather than on when a refresh ran.

**A body that cannot be read is tried again.** A body the blob directory no longer holds when the indexer opens it, or whose bytes fail its name (STORAGE §7), is not `unparseable`: its placement is counted `missing` (§8.2) and folded again by every refresh, stamped again or not, until its body is read for the indexing and, for a calendar item, the expansion, or it holds no body or is gone. Meanwhile a body the index never read leaves its placement matched on its summary (§6), and one it holds keeps what it answered, occurrences and cut included (§7).

**Erasing.** A refresh deleting what an erasure purged (STORAGE §11.5) leaves none of its text in index.db, its pages zeroed as STORAGE §11.5 says and the full-text segments holding its tokens merged away.

## 5. Tokens

**Text is folded before any tokenizer reads it**, in the index and in a query alike: every character lowercased by STORAGE Annex A.2's mapping, then decomposed (Unicode canonical decomposition, NFD), every combining mark of U+0300 to U+036F dropped, and composed again (NFC). `Réunion`, `REUNION` and `réunion` are one word, and a mark of another block (a Devanagari vowel sign, a Hebrew point) is kept. The indexer writes folded text and the query compiler folds every text term, so no tokenizer folds a diacritic and no SQL function is registered.

A tokenizer splits words as SQLite's `unicode61` does with diacritics kept (`remove_diacritics 0`), with no stemming and no trigram substring search. One splitting otherwise (FTS4's `simple`, on ASCII alone) answers other hit sets, and the vectors all the same.

**A word is exact.** A text term matches its folded tokens as written, never a stem or another form of the word, in this version and every later one: a matching that reads other forms is an operator of its own, which §8.3 reserves.

An address is indexed whole, as its local part and as its domain in the `people` field, so `alice`, `example.org` and `alice@example.org` all match and `from:@example.org` is a match rather than a scan. A telephone number is indexed as its digits alone beside the value.

## 6. Extraction

This section is at **revision 1**, bumped, in a minor version once released, by a change to what it extracts from a body or to what §7 expands from one.

A body is extracted once, by hash, into seven fields: `title`, `people` (every name and address, plus §5's address tokens), `body`, `attachment` (part names and media types), `place`, `org`, `note`. Beside `people`, one field per address role of STORAGE Annex A.6 (`from`, `to`, `cc`, `bcc`, `email`, `organizer`, `attendee`) holds that role's names and addresses alone, so `from:jane` is a match on the sender and not on anyone the message names.

| Kind | `title` | `people` | `body` | `attachment` | `place` | `org` | `note` |
| --- | --- | --- | --- | --- | --- | --- | --- |
| mail | `Subject` | `From`, `To`, `Cc`, `Bcc` | the text parts | its attachments' names and media types (STORAGE §14.3) | | | |
| contact | `FN`, `N` components, `NICKNAME` | every `EMAIL`, the `FN` | | | `ADR` | `ORG`, `TITLE`, `ROLE` | `NOTE`, every `TEL` |
| calendar | `SUMMARY` | `ORGANIZER`, `ATTENDEE` values and `CN`s | `DESCRIPTION` | each `ATTACH`'s `FILENAME` (RFC 8607) and `FMTTYPE`, an `ATTACH` stating neither adding nothing | `LOCATION` | | `COMMENT` |

The extraction also records whether it wrote any text into a body's `attachment` field, and whether a card holds a `TEL`, an `ADR`, a `BDAY` and a `PHOTO`, which `has:` reads (§8). A card's `CATEGORIES` values are recorded beside it, each property's list split on unescaped commas and decoded as STORAGE Annex A.4 splits a task's, empty values dropped, folded as Annex A.2 folds `fn`, each once.

Mail extraction MUST walk the MIME tree as STORAGE Annex A.1 walks it, reading every part it reads, the last child of a multipart nothing closes among them, and no part it leaves unread, an entity's own fields read from their first occurrence as A.1 reads them. It MUST decode transfer encodings, decode each text part by its `charset`, decode RFC 2047 and RFC 2231, prefer `text/plain` and reduce `text/html` to text, a reduction this part leaves to the implementation. It SHOULD separate tokens at the boundaries of block-level elements, so the texts of two table cells, two paragraphs or two list items never join into one token, and SHOULD skip the content of the head, style, script and template elements whatever their attributes.

A header field the extraction reads, `Subject` and the address fields here and `In-Reply-To` and `References` in §9, MUST be read as STORAGE Annex A.1 reads one, a field present twice from its first occurrence, so the index holds the subject and the people the summary row states.

A text part SHOULD be decoded as STORAGE Annex A.1 decodes an encoded word's octets, by the WHATWG Encoding Standard's decoder for the encoding its `charset` labels, no byte order mark sniffed, `us-ascii` when it states none (RFC 2046 §4.1.2), and as UTF-8 replaced as Annex A.0 says when no label names one. Attachment content is out of scope.

**The hit-set guarantee (§12) leaves out text reduced from HTML, and a part's text beyond seven-bit ASCII in a charset other than UTF-8**, which this section pins only by recommendation: a word that text alone holds MAY be a hit in one conforming index and not in another. The vectors hold no such word.

A `multipart/encrypted` or `application/pkcs7-mime` body is recorded `encrypted`, headers indexed and body not. Decrypted content is indexed only when the user asks for it, never by default, since it writes the plaintext into index.db (STORAGE §18). A body no parser accepts is `unparseable`, with what could be read. The extraction status is an open vocabulary (STORAGE §13), `ok`, `encrypted` or `unparseable` in this version: a reader MUST read a status it does not know as `unparseable`, which coverage counts so (§8.2) and `is:encrypted` does not match, so a status a later version adds is a minor version.

**Chunks.** The text of the `body` and `note` fields is cut into chunks, numbered from 0 in text order, the `body` field's before the `note` field's, each bounded by UTF-8 byte offsets into the field's text as extracted, before §5's fold:

- **Paragraphs.** A field's text is split into paragraphs at every blank-line run: a line break (LF, or CR LF) followed by one or more lines holding nothing but spaces and tabs, each ended by a line break.
- **Packing.** Paragraphs are packed greedily, in order, into chunks of at most 1024 bytes, a chunk running from its first paragraph's start to its last one's end, the runs between them included. A paragraph that does not fit the chunk being filled starts the next one.
- **Long paragraphs.** A paragraph longer than 1024 bytes is cut into pieces, each ending just after the last space, tab, CR or LF within its first 1024 bytes, else at the last character boundary within them. Every piece but the last is a chunk of its own, and the last is packed as a paragraph.

No other field and no summary is chunked.

*Note:* no answer states a snippet (§8.2). A client showing one cuts it from a hit's chunks, over the text it extracts from the blob, and an embedding index embeds the same chunks.

A placement with no body is matched on its summary and addresses (STORAGE Annex A) alone: `title` from the subject, `fn`, `summary` or a file's `name`, `people` and the role fields from the addresses, every value decoded on Annex A.0's terms. A file (STORAGE §14.3) is matched so, its body or not, its content being out of scope.

## 7. Calendar time

`sort_key` holds a series' first occurrence (STORAGE Annex A.3), so `date:today` cannot be answered from the store for a meeting that started years ago.

The index materialises every occurrence within a **horizon**, default one year back and two forward, each a start and an end as instants, using the resource's `VTIMEZONE`s, `RDATE`, `EXDATE` and `RECURRENCE-ID` overrides:

- An event spans `DTSTART` to `DTEND` or `DURATION`, and with neither one day for a date and no time for a date-time (RFC 5545 §3.6.1).
- A task spans to its `DUE`, a task with a `DUE`, no `DTSTART` and no `RRULE` being one zero-length occurrence at its due time.
- A journal spans its `DTSTART` alone.
- A resource holding overrides and no master (an attendee's single instance) yields each override as an occurrence, spanning its own `DTSTART` to its end by the rules above.
- A series no expander accepts (an `RRULE` with no `DTSTART`) yields no occurrence and MUST NOT fail the pass.
- A series every `RRULE` of which states an `UNTIL` whose date falls before the date its `DTSTART` states has no instance at its `DTSTART`, so it yields no occurrence but those its `RDATE`s and overrides name; an `UNTIL` earlier on the date of `DTSTART` cuts nothing. This departs from RFC 5545 §3.8.5.3, where `DTSTART` defines the first instance of the set, because such a series is the shape a client leaves when it deletes a series from its first instance on, and search then shows what Pimalaya's calendars, which expand with ical-rs, show.
- An item holding no body yields no occurrence, its sort key standing for none, and one whose body the index never read (§4) none until it is read: a date term matches neither, the coverage counting it (§8.2).

**Bounds.** An item writes at most 10,000 occurrences: the first, in the order `start` then `end`, of those overlapping the horizon. An expander examines at most 1,000,000 periods of a recurrence rule, a period being each span of `INTERVAL` times the rule's `FREQ` in turn from the one holding its `DTSTART` (RFC 5545 §3.3.10), whether or not it yields an instance, a period before the horizon counting. It walks at most 10,000,000 instances of a recurrence rule, an instance being each start the rule yields in turn from its `DTSTART`, in its periods' order, whether or not it falls in the horizon or an `EXDATE` removes it, whatever `COUNT` the rule states beyond them. An item a bound stops records its **cut** with its occurrences: the instant from which its occurrences are not all written, the earliest of the start of its 10,001st occurrence, the start of the first period not examined and the start of the first instance not walked, none when no bound stops it. Every occurrence starting before the cut is written. A `VTIMEZONE` observance's rule is examined on the period bound, the offset of the last onset found standing beyond it, and cuts nothing.

A zoned time resolves through the resource's own `VTIMEZONE`, else the IANA time zone database by `TZID`, else as floating, as STORAGE Annex A.3 orders them. A wall time a transition makes ambiguous or skips, a recurrence instance's included (RFC 5545 §3.3.10), takes the offset in effect before the transition, as there. A floating time and a date are read in the time zone the indexer states, an IANA name, `UTC` when it states none. The index records that zone, its **floating zone**, `UTC` when the index is created.

**An agenda.** A range's occurrences are listed one row each with its instants, in the order `start`, then `seq`, then `collection`, on §8.1's overlap rule, an occurrence of zero length falling in the range it starts; a range outside the horizon, or past an item's cut, is incomplete there as in a query's coverage (§8.2).

**Re-expansion.** An item's occurrences and cut are those an expansion under the current horizon, time zone database, indexer's zone and revision of §6 gives, so it is expanded again when its body or one of these changes. A re-expansion that cannot read an item's body (§4) MUST keep the occurrences and the cut the index held for it, never replace them by none, the placement counted `missing` in coverage until its body is read. A query outside the horizon MUST say so in its coverage (§8.2).

The index records the time zone database version its occurrences stand under, as the database names its release (IANA's `2026b`), empty with none. An indexer whose database names another version MUST re-expand every live calendar item and record the new version in the refresh that sees it. An indexer stating another zone than the index's floating zone MUST likewise re-expand every live calendar item and record its zone in the refresh that sees it, so two indexers in two zones never leave occurrences read in both.

## 8. The query language

A query is whitespace-separated terms, implicitly conjoined, with `or`, `not`, parentheses and quoted phrases; a term is free text or `field:value`; a trailing `*` is a prefix wildcard. Free text matches every field of §6. §8.3 is the grammar, §8.4 the answer to a query it refuses, and §8.5 how a text term matches: a full-text engine's own syntax is never accepted raw.

| Field | Meaning |
| --- | --- |
| `subject:` `title:` `summary:` | the `title` field |
| `body:` | the `body` field |
| `from:` `to:` `cc:` `bcc:` `attendee:` `organizer:` `email:` | for a value containing `@`, the items whose summary states that address in the role (STORAGE Annex A.6), a bare `@domain` any address of the domain; the role's own field otherwise |
| `with:` | any role, the same way over the `people` field |
| `person:` | contacts whose `title` matches, expanded to `with:` over the addresses their cards state |
| `tag:` `flag:` | a store flag (§10), as written: a system flag (§3) read from the store, any other flag, a keyword, from the index |
| `is:` | `unread` the absence of `\Seen`; `read`, `flagged`, `answered`, `draft` the presence of `\Seen`, `\Flagged`, `\Answered`, `\Draft`, read from the store; `encrypted` the extraction status (§6) |
| `has:body` `has:attachment` | a stored body; a message whose summary marks an attachment, with or without its body (STORAGE Annex A.1), or a calendar item whose body's `attachment` field (§6) is non-empty; a contact or a file never |
| `has:phone` `has:address` `has:birthday` `has:photo` | a card holding a `TEL`, an `ADR`, a `BDAY`, a `PHOTO` (§6); any other kind never |
| `kind:` | `mail`, `contact`, `event`, `task`, `journal`, `file` |
| `status:` | a task's `STATUS` as its summary states it (STORAGE Annex A.4): `needs-action`, `in-process`, `completed`, `cancelled`; a task stating none, and any other kind, matches none |
| `priority:` | a task's `PRIORITY` as its summary states it (STORAGE Annex A.4, RFC 5545 §3.8.1.9): `high` 1 to 4, `medium` 5, `low` 6 to 9, `none` absent or 0; any other kind matches none |
| `category:` | a task's `CATEGORIES` as its summary lists them (STORAGE Annex A.4) or a card's (§6): one value whole, both sides folded as STORAGE Annex A.2 folds `fn`, never a word of it; any other kind never |
| `label:` | an item's label (STORAGE §4.3), a value under the key `pimdir/label` read from the store, never from the index: one value whole, both sides folded as STORAGE Annex A.2 folds `fn`; every kind |
| `property:` | an item's property (STORAGE §4.3), written `<key>=<value>`, the key before the first `=`: the value whole under that key, byte for byte, read from the store, never from the index; every kind |
| `account:` `collection:` `folder:` | the store's axes, `folder:` an alias |
| `date:` `when:` | an instant or a range (§8.1) |
| `thread:` | the link id of any node of a thread (§9), a member or a parent no member is: the present members of that thread in every account holding one, an `account:` term narrowing them as it narrows any hit |
| `id:` | a link id or a `seq`: a value of ASCII digits alone names the item of that `seq` and every item whose link id it is, a hit set rather than a guess, any other value a link id |
| `mid:` | a message's `Message-ID` as its summary states it (STORAGE Annex A.1), matched whole and byte for byte, its angle brackets dropped when written within them; any other kind never |
| `linked:` | the items at the other end of the named item's references, either direction, read from the store: `linked:<id>`, or `linked:<role>:<id>` for one role of STORAGE §14.2 (named or `x-` and a name), the item named as `id:` names it; a value whose text before its first colon is no such role is all id, and one naming a role and no id after its colon (`linked:sender:`) is refused (`invalid-value`) |
| `attachment:` `mimetype:` | the `attachment` field |
| `location:` | the `place` field |
| `changed:` | change stamps (STORAGE §4.5), a stamp or a range, both ends included |

### 8.1 Dates

A `date:` or `when:` value is a point or a range of points (`date-value`, §8.3):

- A year, a month, a day, `today` and `yesterday` each cover their calendar span, in the time zone the client states, an IANA name, UTC when it states none: from the first instant of its first day there to the first instant of the day after its last. A client SHOULD state the user's zone, the one its indexer states as its floating zone (§7), so the days a query names and the floating times and dates the index placed agree.
- An instant (`2026-08-01T10:00`, `2026-08-01T12:00:30+02:00`) covers its own minute, or its second when it states one, read at its offset (`Z` for UTC), else in the client's zone, a local time a transition skips read with the offset in force before it (`02:30` in a gap from 02:00 to 03:00 is 03:30 after it), one it repeats as its first occurrence.
- A relative amount (`30min`, `5h`, `3d`, `2w`, `2mo`, `1y`: minutes, hours, days of 24 hours, weeks of seven days, calendar months, calendar years) names the instant that long before `now`. A month or a year is counted on UTC's calendar, to the same day and time, a day the month reached lacks landing on its last (31 March less `1mo` is the last day of February).
- A single point is its span, a single relative amount the span from its instant to `now`; a range `a..b` runs from the start of `a`'s span to the end of `b`'s, either side open, a relative amount there spanning its instant alone, so `2w..2w` is the empty span and `..2w` ends two weeks before `now`.
- A bound no instant of a four-digit year states is open: a span ending past 9999-12-31T23:59:59Z is open on that side, and so is one starting before 0000-01-01T00:00:00Z, which a relative amount reaches.

Every span is half-open, and one whose end is not after its start is empty: it holds no instant and matches nothing, whatever the kind. Mail compares `sort_key`. An event, task or journal compares occurrences (§7), one overlapping a range when it starts before the range ends and ends after the range starts, a zero-length one when it starts inside it. A contact or a file has no date, a file's `sort_key` being its name, and is excluded from a date-bounded query unless `kind:contact` or `kind:file` names it.

A range leaves the horizon when it starts before the horizon's start or ends after its end, an open side always, and only in a query whose kinds and collections can hold a calendar item.

A client's zone and the index's floating zone are compared as names, a client stating none stating `UTC`. Where they differ, the answer to a query holding a `date:` or `when:` term, whose collections (§8.2) hold a calendar one, says so in its coverage.

### 8.2 Semantics

- **A hit is `(account, seq)`**, one per item per account, carrying its placements (STORAGE §9.2): every live placement of the public id in the account's collections, `account` `NULL` for those of no account, in collection order, each with its link id, flags, body, sort key and level as a listing reads them, its collection's kind, the `kind:` value it answers to (§8) and its title; a tombstone or a retained row is none. An implementation MAY flatten to one row per placement on request.
- **Tags** are per placement in the store and per hit in the query: `tag:x` matches when any placement carries `x`, `not tag:x` when none does. A system flag likewise: `is:read` matches when any placement holds `\Seen`, `is:unread` when none does.
- **A text term** likewise holds for a hit when any of its live placements in the account matches it through its document (§3), and `not` when none does. Several text terms each hold or not on their own, so `a b` holds for a hit one of whose placements holds `a` and another `b`. A hit the store no longer holds is never answered.
- **Order** is one of five, each one value with its direction, `newest-first` by default:
  - `newest-first`: `sort_key` descending, the undated (contacts and files) last in their own `sort_key` ascending;
  - `oldest-first`: `sort_key` ascending, the undated last likewise;
  - `title`: the item's title (a message's subject, a card's `fn`, a calendar component's summary, a file's name) folded as Annex A.2 folds `fn`, ascending, a title-less item first;
  - `sender`: a message's sender address (STORAGE Annex A.1) folded likewise, ascending, a message stating none and every other kind last, in `newest-first` order among themselves;
  - `relevance`: the index's own, best first, bm25 RECOMMENDED; an index without one MAY refuse `relevance` and say so.
- **A hit's key** in the order is the greatest `sort_key` among its live placements, one key where the store shares a `seq` by agreement on the date (STORAGE §9.1); where they differ, an implementation MAY read the key among the placements of the query's collections, or, when two `collection:` or `folder:` conjuncts leave none, of the first one's. A hit needs no placement in the query's collections: `collection:a collection:b` answers the items filed in both.
- Ties go to `seq`, then the account. A threaded listing (§9) orders its threads by their first hit in the order.
- **The query's collections** are every collection of the store, less those an `account:`, `collection:`, `folder:` or `kind:` term rules out by its account, its id or its kind, `event`, `task` and `journal` each naming the calendar kind. Only a conjunct of the whole query rules any out, a group that is itself one lending the query its own conjuncts at any depth, so `(collection:a) x` and `collection:a x` have one scope. A term negated, beside an `or`, or inside a group negated or beside an `or`, rules none out.
- **Coverage is part of the answer**:
  - per kind among the query's collections, mail, contacts and calendars (never files, §6), four counts, each a key of its own and counted per placement: `bodiless`, the live items holding no body; `missing`, the placements whose body could not be read (§4); `unparseable`, those whose body the extraction recorded so or under a status the reader does not know (§6); `encrypted`, likewise. A `missing` placement whose body the index holds as `unparseable` or `encrypted` counts under both keys;
  - whether a date range left the horizon (§8.1);
  - for a query bounded by date, how many calendar items of its collections had their occurrences cut before the range's end (§7), every cut item for a range open there;
  - whether the zone the query stated differs from the index's floating zone, where a date term can reach a calendar item (§8.1), which leaves an answer complete;
  - the lag;
  - per hit, whether it matched on its body or its summary;
  - whether the answer is complete.
- **A term reads a body** when the index answers it from what the extraction recorded of one, wherever it stands in the query, negated or not, and reads these kinds' alone: a text term (§8.5) mail, contacts and calendars; `date:` and `when:` calendars (§7); `has:attachment` calendars, a message's mark being the store's; `thread:` mail, a bodiless message naming its parent by its `In-Reply-To` alone (§9); `has:phone`, `has:address`, `has:birthday`, `has:photo` and `category:` contacts, a task's categories being the store's; `is:encrypted` mail.
- **An answer is complete** when all of these hold:
  - the lag is zero and the temporal axis is `full`;
  - no date range left the horizon, and no calendar item was cut before the range's end;
  - no kind counts a `bodiless` item, a `missing` or an `unparseable` placement while a term of the query reads a body of that kind;
  - mail counts no `bodiless` item while the query holds `has:attachment`, a bodiless message's mark being a guess its body corrects (STORAGE Annex A.1);
  - no `encrypted` placement is counted while the query holds a text term matched in the `body` or the `attachment` field (§8.5): free text, `body:`, `attachment:` or `mimetype:`.
- **The lag** is store-wide: the stamps the store drew above the last one the index folded (§4), zero exactly when the index has folded every change, else an upper bound on the rows a refresh has yet to fold.
- **Flags are as fresh as the store.** A system flag term (`is:read`, `is:unread`, `is:flagged`, `is:answered`, `is:draft`, and a `tag:` or `flag:` naming a system flag) reads the store as it stands when the query runs, every term the index answers the store as the index last folded it.
- **Coverage has a temporal axis**: whether the store holds every member of the queried collections over the query's date range, open on a side the query does not bound, read from their sources' coverage (STORAGE §10). It is `full`, or `bounded` with `since`, the instant below which a queried collection is not known complete (a `covered_since` above the range's start, else `null`), `until`, the instant from which one is not (a `covered_until` below the range's end, else `null`), and `filling`, true when a source of a queried collection never closed a round. A collection no source syncs is complete. The collections' answers roll up conservatively: the highest `since`, the lowest `until`, `filling` when any is.
- **A page.** A client MAY answer the first hits in the query's order after a cursor rather than every hit. A cursor is a position in the order, never a hit: the key the last hit it answered holds in the order (its sort key, its title or sender folded, or its rank), then that hit's `seq`, then its account. A page answers the hits past that position as the index stands when the page is asked, a refresh between two pages included: a hit that moved before the position is not answered, one that moved past it may be answered again, and the hit the position was read from need not be held any more. This holds alike for `relevance` and for a threaded listing, whose position is read from the first hit of the last thread it answered. Every page walked to the end over an index no refresh moved answers the hits and the order one whole answer does. A cursor is the client's own: one it cannot read is its own to refuse, under no code of §8.4.

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
point        = year / month / day / instant / %s"today" / %s"yesterday" / relative
year         = 4DIGIT
month        = 4DIGIT "-" 2DIGIT            ; 01 to 12
day          = 4DIGIT "-" 2DIGIT "-" 2DIGIT ; a date of the Gregorian calendar
instant      = day %s"T" hour ":" minute [ ":" second ] [ offset ]
hour         = 2DIGIT                       ; 00 to 23
minute       = 2DIGIT                       ; 00 to 59
second       = 2DIGIT                       ; 00 to 59
offset       = %s"Z" / ( "+" / "-" ) hour ":" minute
relative     = 1*6DIGIT ( %s"min" / %s"h" / %s"d" / %s"w" / %s"mo" / %s"y" )
stamp-value  = stamp / stamp ".." [ stamp ] / ".." stamp
stamp        = 1*18DIGIT
property-value = property-key "=" 1*vchar  ; the value of at most 1,024 bytes of UTF-8
property-key = key-part "/" key-part       ; at most 64 characters
key-part     = 1*( %x61-7A / DIGIT / "." / "_" / "-" )
```

- **Tokens** are `(`, `)`, a phrase, a field term, a text, an operator and a `-` beginning a primary, read longest first: a text, a field term and a value run to the next `sep`, parenthesis or double quote. A `sep` is otherwise insignificant, and a parenthesis or a phrase needs none beside it.
- **Operators.** A text spelling `and`, `or` or `not`, in any case, is the operator, never a term; to search the word, quote it.
- **Negation.** A `-` at the start of a primary (at the query's start, after whitespace, after `(`, or after another `-` or `not`) is `not`, never inside a word: `stand-up` is one text and `from:-x` a value, while `-"weekly sync"`, `-from:x` and `--x` negate.
- **Precedence.** `not` binds tighter than `and`, explicit or by juxtaposition, which binds tighter than `or`; parentheses group.
- **Fields.** A word holding a colon outside quotes is a field term, never free text. Its field is the text before the first colon and MUST be a name of §8's table, as written; anything else is refused (`unknown-field`). The value is the rest of the word, colons included, or the phrase right after the colon.
- **Phrases** run to the next `"`, with no escape. Nothing inside one is an operator, a field or a wildcard: its text is tokenised as §5 says and matched as a phrase (§8.5).
- **Wildcard.** A `*` MUST be the last character of a text or of a text field's value, after two characters or more. Anywhere else outside a phrase it is refused (`invalid-wildcard`). The text fields are `subject:`, `title:`, `summary:`, `body:`, the role fields, `with:`, `person:`, `attachment:`, `mimetype:` and `location:`. The value of a role field or of `with:` holding `@` is an address, not text (§8's table); in another text field `@` is a character as another (`subject:a@b`).
- **Reserved forms.** Three spellings are kept for operators a later version gives, and refused now in every field (`reserved-form`), so each comes as a minor version: a text or a value beginning with `~` (a stemmed word), `~` alone included; a text or a value of two characters or more beginning with `/` (a regular expression, `subject:/foo` included); and a value beginning with `{` (a subquery: `thread:{from:jane}`). Anywhere else `~`, `/` and `{` are characters as others (`x~y`, `a/b`, a text `/` or `{x}`), and a phrase is never a reserved form (`"~meeting"`).
- **Values.** `kind:`, `is:`, `has:`, `status:` and `priority:` take `kind-value`, `is-value`, `has-value`, `status-value` and `priority-value`; `date:` and `when:` take `date-value`, `changed:` `stamp-value`, `property:` `property-value`; every other field takes its value as written, a phrase value read the same, its quotes aside. A `label:` value, and a `property:` value's part after its `=`, is one a property may hold (STORAGE §4.3): 1 to 1,024 bytes of UTF-8 holding no U+0000, others, `""` included, refused (`invalid-value`), as is a `property:` value whose key no `property-key` reads or one past 64 characters. A key under `pimdir/` this version does not define is read as any other. The digit bounds of `relative` and `stamp` keep every stamp within a signed 64-bit integer.
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
| `dangling-operator` | an `and` or `or` missing a side, a `not` with nothing after it, a `-` followed by whitespace, a `)` or the end | the `-` so followed, else the first `not` or `-` of the run missing its term (`not or x` and `-or x` answer the `not` and the `-`), else the `and` or `or` missing its side |
| `unknown-field` | a field that is not in §8's table | the field and its colon |
| `invalid-value` | no value after the colon, a value out of `kind-value`, `is-value`, `has-value`, `status-value` or `priority-value`, a `changed:` value no `stamp-value` reads, a `label:` value or a `property:` value past STORAGE §4.3's bounds, or one without `=`, a `linked:` value naming a role and no id | the value, or the term when no value follows its colon |
| `invalid-date` | a `date:` or `when:` value no `date-value` reads | the value |
| `reserved-form` | a text or a value §8.3 reserves | the text, or the value |
| `invalid-wildcard` | a `*` §8.3 does not accept | the first `*` of the text or value |
| `limit-exceeded` | a query past a limit of §8.3 | as §8.3's table says |

A query with several faults answers one, found in four passes: the length, the phrases, the parentheses with their nesting, then the terms and operators in reading order, their count among them. The first pass to find a fault answers its leftmost: a query past the length is refused whatever else it holds, and an unbalanced parenthesis left of the one opening the 33rd group answers first.

A term is checked for its count, then its field, then a missing value, then a reserved form, then the wildcard, then its value, so a later version giving a form its meaning still refuses an unknown field as before. A value's span includes a phrase's quotes. A phrase is a value, `""` included: `kind:""` is a value out of `kind-value`, and `subject:""` a text term yielding no token, which matches no item (§8.5).

### 8.5 Text terms

A text, a phrase and the value of a text field are each a **text term**, the value of a role field or of `with:` holding an `@` excepted, which is an address (§8.3). A text term is matched on the index's tokens, so every index answers one hit set:

- Its text, a phrase's between its quotes and a value's without its trailing wildcard, is folded as §5 says and split into tokens by the index's tokenizer, which splits the indexed text alike.
- It matches a field holding those tokens consecutively and in that order, each token exactly (§5); a term ending with the wildcard reads its last token as the prefix of one. A term yielding no token matches no item.
- No character of the term is syntax of the full-text engine: a character the tokenizer keeps in no token only separates tokens, whatever the engine makes of it (FTS5's `^`, `+`, `{`, `:`, a `*` inside a phrase, `NEAR`, `AND`, `OR`, `NOT`), and a word is a token in any case.
- Free text matches in every field of §6, a field term in the field §8's table maps it to and in no other. A bodiless placement matches on its summary's fields (§6) alone.

*Note:* an FTS5 index matches a text term by one FTS5 string, the folded text with every `"` doubled and every U+0000 written as a space, quoted, then ` *` for the wildcard, after `{column} : ` for a field term: `body:^report` compiles to `{body} : "^report"`, matching `report` anywhere in a body, where `{body} : ^report` would match it first.

## 9. Threads

Mail only. A message's `parent` is its first `In-Reply-To` id, else the last `References` id (RFC 5322 §3.6.4), from the headers at `Full`, and for a bodiless item the first `In-Reply-To` id its summary lists (STORAGE Annex A.1). Each is read as §6 reads a header field, from its first occurrence.

A **member** is a message a live mail placement holds. Every id a member bears or names as its parent is a node, present in the store or not, and no other id is one, so two replies to a parent nobody holds are one thread, which the parent joins when it arrives. A cycle is broken by ignoring the edge that would close it.

A thread is the connected set over those nodes, as its members stand. Its id is the link id of the present member with the lowest `(sort_key, link_id)`, and its first and last dates its members' lowest and highest sort keys. No joining by subject.

**A message that leaves prunes its thread.** When the last mail placement holding a link id goes, the threads become those a rebuild gives: a node no member bears names no parent, and goes when none names it. A purged message thus stays only as the phantom parent a member names.

`thread:` takes the link id of any node, a member or a parent no member is, and returns the present members of its thread in every account holding one, an `account:` term narrowing them. A threaded listing collapses hits to threads with count, first and last date.

## 10. Tags

A tag is a flag of the placement (STORAGE §13), so it syncs with the sources that carry keywords.

Tagging from a query is a store write: one `set-flags` action per placement of each hit, staged through the queue (STORAGE §15) as a producer. The index's keywords are folded from the feed and hold no state of their own, and a tag naming a system flag is read from the store (§8).

A label is the private counterpart: a property of the item (STORAGE §4.3), never synced, which `label:` reads from the store and `tag:` never does. Labelling from a query stages one `set-property` per hit (STORAGE §15.3), on a collection holding its item live: the label is the item's, so every placement of it holds the label.

## 11. Test vectors

vectors/search/ holds the fixture store and the queries every conforming implementation MUST answer alike, each file stating the version of its format, `v` 6 for queries.json, `v` 3 for store.json, `v` 1 for chunks.json, `v` 7 for refresh.json and `v` 2 for extraction.json, and conforming to its JSON Schema under vectors/schema/; vectors/README.md says how each reads. store.json is the store, an item stating `unreadable` one whose body the indexer cannot read (§4); queries.json the cases and agenda windows (§7) over it; chunks.json field texts and their chunks (§6); refresh.json stores, each with steps of an owner's write, the feed it leaves and the queries answered after it (§4, STORAGE §4.5), a query asked by pages continuing one an earlier step asked (§8.2); extraction.json stores of their own, each built as store.json is, and the cases answered over each, what extraction reads of a body kind by kind (§5 to §7).

A case answers `hits` as `(account, seq)` pairs, a list when it says `ordered` and a set otherwise, the `threads` of a threaded listing (§9), or the `error` of a refusal, its `code`, `start` and `end` compared and the rest not. Where it states them, it also compares what §8.2 reports: `horizon_left`, `cut`, the `temporal` coverage, the `coverage`, whether it is `complete`, `zone_differs`, and what each hit it names under `matched` matched on, `body` or `summary`. A case stating a `zone` is asked stating it (§8.1), on an index whose floating zone (§7) is that zone or the case's `index_zone`; one stating a `now` resolves its dates against it.

An implementation builds the store, takes out of its blob directory the body of each item stating `unreadable`, indexes it at `now` stating no zone, so `UTC` (§7), and compares, indexing it again for the cases stating a zone. For refresh.json it then, per step, reads the cursor, applies the write through its owner, compares the feed above that cursor (STORAGE §4.5), refreshes the index and answers each query, a step stating `lagging` answering before the refresh, with terms the store answers as it stands alone (§8.2), and a query stating `page` answering its `limit` hits past the position the query it continues ended on. For extraction.json it builds and indexes each case's store at the file's `now` and answers its cases as queries.json's.

The cases bind every index (§12), but a case sorted by `relevance` binds its order only where the index ranks by bm25: another compares its hits as a set, a query asked by pages in that order binding such an index alone, and one refusing `relevance` skips it. checks/vectors.py validates the vectors and re-derives what a case fixes without an index (vectors/README.md lists it), the limits read from §8.3's table among it; only an implementation runs a case against the store.

## 12. Conformance

An implementation offering search conforms by one profile or both, stated as STORAGE §17 says (`search-v1.0.0 indexer`, `search-v1.0.0 query client`) with the shape of the index it builds or reads (§2), and MUST meet every section its row names and answer the vectors it names.

**The hit-set guarantee.** Whatever its layout and full-text module (FTS5, FTS4, FTS3 or none), an index answers the hit sets vectors/search/ gives, folding as §5 says and matching as §8.5 says, but for the text §6 leaves out; its order by relevance is its own (§8.2).

| Profile | What it does | Owes | Vectors |
| --- | --- | --- | --- |
| indexer | a store reader (STORAGE §17) writing index.db under index.lock | §2 to §7, §9 | store.json indexed, every case of queries.json answered on its index by a conforming query client; each store of extraction.json likewise, with its cases; chunks.json; every step of refresh.json, its writes made through a conforming owner |
| query client | reads index.db, the store beside it | §2's refusal, §5, §8, §9, §10, a tag enqueued as a STORAGE producer | every case of queries.json and of extraction.json (§11), on an index a conforming indexer built from the store it is asked over |

Both meet STORAGE §18, index.db holding the text of every body indexed, and an indexer erases as §4 says.
