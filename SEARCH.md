# Pimdir search specification

Status: draft

The search part of the pimdir standard: a full-text index over a store ([STORAGE.md](./STORAGE.md)) and the query language over it, cross-domain from the first line. A query names people, dates, tags, kinds and text and answers with items of every kind: a person's card, the mail they sent and the meetings they attend are one result set.

An implementation MAY omit search; one that offers it MUST conform, so every client on one store answers `is:unread from:jane` the same way.

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

- The index MUST be a SQLite database named index.db in the store directory (STORAGE §3), every table `STRICT`, `PRAGMA foreign_keys = ON`.
- Implementations MUST require **SQLite ≥ 3.43** with FTS5, for `contentless_delete`. This floor is the index's alone.
- The schema is [migrations/index/0001_init.sql](./migrations/index/0001_init.sql), its version in the index's own `PRAGMA user_version`, mirrored in `index_meta.version`. An index at another version, or whose `index_meta.tokenizer` differs from §5's, MUST be rebuilt: there are no index migrations.
- The statements are [queries/index/search.sql](./queries/index/search.sql), prepared with the store attached read-only as `store`.

## 3. The index

The **indexer** is a store reader (STORAGE §8): read-only on pimdir.db, no store lock, running whether or not an owner syncs. It is the sole writer of index.db and MUST hold an exclusive advisory lock on index.lock for a refresh, on the owner lock's terms. **Query clients** open index.db read-only, any number at once, no lock.

The main database is index.db, pimdir.db attached as `store` through a read-only URI, so one statement joins both (`hit`, `coverage`).

Tagging is a store write through the queue (§10). Nothing writes the store through the index.

The index holds one `object` row and one `object_text` FTS row per indexed body, keyed on the store's hash, so a body filed in three collections is tokenised once; one `placement` row per live item seen; a `summary_text` row per placement with no body; the derived `flag`, `occurrence`, `thread` and `message` tables; and `index_meta`, the store cursor folded in (§4) and the horizon (§7).

## 4. Refresh

A refresh folds the change feed (STORAGE §4.5): every item stamped above `index_meta.store_change`, in stamp order, in read transactions of bounded size so the store's WAL still checkpoints.

Per row: the body is indexed if its hash is new (§6); the placement is upserted; summary text is written while it has no body and dropped when it gains one; flags are replaced; occurrences are re-expanded when the body changed (§7); the thread is updated (§9). A deleted or retained row loses its placement rows; its body's text stays until the object goes.

When `store_meta.purges` moved, or a collection stamp did (a rename stamps the new id only), the indexer reconciles keys: `placements_gone` and `objects_gone` name what the store no longer holds. The cursor `(next_change, purges)` read before the pass is written by `set_index_cursor` in the transaction completing it, so a crash replays and skips nothing.

A store from before the feed carries stamps of `0` and is indexed whole once. Extraction MAY run in parallel; the index is written by one transaction per batch.

## 5. Tokens

The tokenizer is `unicode61 remove_diacritics 2`, no stemming, `prefix = '2 3'` for the trailing wildcard (§8), recorded in `index_meta.tokenizer`. No stemming because FTS5's only stemmer is English-only; no trigram substring search because it triples the index for a feature the target audience's tools lack.

An address is indexed whole, as its local part and as its domain in the `people` field, so `alice`, `example.org` and `alice@example.org` all match and `from:@example.org` is a match rather than a scan. A telephone number is indexed as its digits alone beside the value.

## 6. Extraction

A body is extracted once, by hash, into seven fields: `title`, `people` (every name and address, plus §5's address tokens), `body`, `attachment` (part names and media types), `place`, `org`, `note`.

| Kind | `title` | `people` | `body` | `attachment` | `place` | `org` | `note` |
| --- | --- | --- | --- | --- | --- | --- | --- |
| mail | `Subject` | `From`, `To`, `Cc`, `Bcc` | the text parts | part names and media types | | | |
| contact | `FN`, `N` components, `NICKNAME` | every `EMAIL`, the `FN` | | | `ADR` | `ORG`, `TITLE`, `ROLE` | `NOTE`, every `TEL` |
| calendar | `SUMMARY` | `ORGANIZER`, `ATTENDEE` values and `CN`s | `DESCRIPTION` | `ATTACH` names | `LOCATION` | | `COMMENT` |

Mail extraction MUST walk the MIME tree, decode transfer encodings, transcode charsets, decode RFC 2047 and RFC 2231, prefer `text/plain` and reduce `text/html` to text. Attachment content is out of scope.

A `multipart/encrypted` or `application/pkcs7-mime` body is recorded `encrypted`, headers indexed and body not; indexing decrypted content is an opt-in that writes plaintext into index.db and MUST be documented as such. A body no parser accepts is `unparseable`, with what could be read.

A placement with no body indexes its summary row and address rows into `summary_text`: `title` from the subject, `fn` or `summary`, `people` from the addresses. That keeps a headers-only replica searchable, and it is dropped once the body is indexed. Every value is decoded on Annex A.0's terms.

## 7. Calendar time

`sort_key` holds a series' first occurrence (STORAGE Annex A.3), so `date:today` cannot be answered from the store for a meeting that started years ago. The index materialises every occurrence within a **horizon**, default one year back and two forward, into `occurrence(start, end)` as instants, using the resource's `VTIMEZONE`s, `RDATE`, `EXDATE` and `RECURRENCE-ID` overrides.

An event spans `DTSTART` to `DTEND` or `DURATION`, a task to its `DUE`, a journal its `DTSTART` alone.

An item is re-expanded when its body changes and when the horizon rolls, which re-expands only the recurring items whose `until` is absent or beyond the old horizon (`items_to_reexpand`). A query outside the horizon MUST say so in its coverage (§8).

## 8. The query language

A query is whitespace-separated terms, implicitly conjoined, with `or`, `not`, parentheses and quoted phrases; a term is free text or `field:value`; a trailing `*` is a prefix wildcard. Free text matches every field of §6. FTS5's own syntax is never accepted raw.

| Field | Meaning |
| --- | --- |
| `subject:` `title:` `summary:` | the `title` field |
| `body:` | the `body` field |
| `from:` `to:` `cc:` `attendee:` `organizer:` `email:` | the role's `item_address` seek for a value containing `@` (a bare `@domain` seeks the domain), the `people` field otherwise |
| `with:` | any role, the same way |
| `person:` | contacts whose `title` matches, expanded to `with:` over their `email` rows |
| `tag:` `is:` `flag:` | a store flag (§10); `is:unread` is the absence of `\Seen`, `is:retained` includes retained items, `is:encrypted` the extraction status |
| `has:body` `has:attachment` | a stored body; `mail_summary.attachment` = 1 or a non-empty `attachment` field |
| `kind:` | `mail`, `contact`, `event`, `task`, `journal` |
| `account:` `collection:` `folder:` | the store's axes, `folder:` an alias |
| `date:` `when:` | an instant or a range (§8.1) |
| `thread:` `id:` | a thread id (§9); a link id or a `seq` |
| `attachment:` `mimetype:` | the `attachment` field |
| `location:` | the `place` field |
| `changed:` | a range over `items.changed` |

### 8.1 Dates

A value is an ISO date or month, a keyword (`today`, `yesterday`), a relative amount (`2w`, `3d`, `1y`), or a range `a..b` with either side open. A single value is the range covering it. Mail compares `sort_key`; an event, task or journal compares occurrences (§7); a contact has no date and is excluded from a date-bounded query unless `kind:contact` names it.

### 8.2 Semantics

- **A hit is `(account, seq)`**, one per item per account, carrying its placements (STORAGE §9.2). An implementation MAY flatten to one row per placement on request.
- **Tags** are per placement in the store and per hit in the query: `tag:x` matches when any placement carries `x`, `not tag:x` when none does.
- **Order** is `sort_key` descending by default, contacts last; `name` ascending; `relevance` by FTS5 `bm25`.
- **Retained items are excluded** unless `is:retained` asks.
- **Coverage is part of the answer**: how many live items in scope have no body (`coverage`), whether the range left the horizon, and per hit whether it matched on its body or its summary.
- A snippet is re-read from the blob for the hits shown.

## 9. Threads

Mail only. A message's `parent` is its first `In-Reply-To` id, from `References` and `In-Reply-To` at `Full` and from `mail_summary.in_reply_to` for a bodiless item. A thread is the connected set of messages linked by parents; its id is the link id of the member with the lowest `(sort_key, link_id)`, recomputed when threads join. No joining by subject.

`thread:` returns the members; a threaded listing collapses hits to threads with count, first and last date.

## 10. Tags

A tag is an `items.flags` entry, so it syncs with the sources that carry keywords and needs no dump and restore. Tagging from a query stages one `set-flags` action per placement of each hit through the queue (STORAGE §15), as a producer. The `flag` table is rebuilt from the feed and holds no state of its own.

## 11. Test vectors

vectors/search/ holds the fixture store and the queries every conforming implementation MUST answer alike:

`store.json`, collections (`id`, `account`, `kind`) and items (`collection`, `seq`, `link_id`, `flags`, and a `fixture` or a `summary` for a bodiless item); `queries.json`, cases with a `query`, an optional `sort`, the `now` relative dates resolve against, the expected hits as `(account, seq)` pairs (ordered when the sort says so, a set otherwise) and the expected coverage.

An implementation builds the store, indexes it at `now`, and compares. checks/vectors.py validates that every fixture and placement resolves; only an implementation runs a case. Tokenisation is pinned by cases whose hits depend on diacritics, a domain token or a digits-only telephone number.
