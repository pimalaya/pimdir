---
cairn: tasks
change: scoped-mail-sync
---

# Tasks

Ordered: each block needs the ones above it, except 1, which can start at once.

## 0. Measure (test accounts only, never a real box)

- [ ] IMAP: Stalwart or Dovecot seeded with ~100k synthetic mails; time `UID FETCH (UID FLAGS INTERNALDATE ENVELOPE)` with `BODY.PEEK[HEADER.FIELDS (CONTENT-TYPE)]`, against `BODYSTRUCTURE`
- [x] Graph, on MOA's test tenant: `$deltatoken=latest` ignored, message delta newest first, summary `$select` at 1,000 a page (proposal, measured 2026-10-07)
- [ ] Graph: skip token lifetime, for resuming an interrupted round
- [ ] Gmail: metadata reads per second when paced near 40, batched
- [ ] Store: inserts per write at 1k, 2k and 5k rows, natively and over JNI
- [ ] Record in android docs/performance.md and moa docs/plan/findings.md; confirm or lower the default page sizes (proposal §2)

## 1. Fixes with no spec change

- [ ] neverest `msgraph`: `date` from `sentDateTime` (`message_date`)
- [ ] Android `graph_mail`: the same; `sentDateTime` in `MESSAGE_SELECT`
- [ ] io-msgraph: a way to send `Prefer: odata.maxpagesize`; neverest and the Android bridge send 1,000 on message delta, with the summary `$select`
- [ ] neverest `imap`: `delete_message` by `UID EXPUNGE` on the one UID, the push rejected on a server with neither UIDPLUS nor IMAP4rev2
- [ ] neverest: `Retry-After`, back-off on 429, 503 and Gmail quota errors, `throttled { source, until }` in the report
- [ ] Android bridge: the same back-off
- [ ] neverest and the Android bridge: Gmail paced near 40 reads a second, below the 250-unit quota

## 2. pimdir (this repository)

- [x] SYNC.md §4: paged enumeration (page, resume cursor, last page), every member named with its meta
- [x] SYNC.md §5: scope (in-scope rule, two-day margin, absence only in scope, explicit removals always, local changes always), rounds stamped and closed, checkpoint bound to its scope
- [x] SYNC.md §3, §5, §6, §12: probes and `Probed` removed; creates wait for the page that lands them; naming at enumeration on §6's identity rules
- [x] STORAGE.md: coverage and the open round per `(collection, source)`; the round stamp on bindings; `collect_before`; the `probes` table and its statements removed
- [x] Annex A: the attachment mark without the body (the source's flag, else `multipart/mixed`), replaced by the walk of the parts
- [x] migrations/storage: coverage, round and stamp columns; `probes` dropped (level 0 rows read as meta to revisit); queries: `set_coverage`, `collect_before`, `count_mail`, per-day and unread counts, sender and subject `LIKE`
- [x] vectors: a paged round (interrupted, resumed, restarted), an old `Date` received today, a future `Date`, no `Date`, an explicit removal out of scope, a widening, a collection, a create landed by a page, the attachment mark both ways; in every one, no `Remove` pushed that the consumer did not stage
- [x] checks/invariants.sh; GUIDE.md, OVERVIEW.md
- [ ] log entry

## 3. io-pimdir

- [ ] Re-vendor schema and statements; reconcile on open
- [ ] `PimdirRemoteItem` carries link id, summary and sort key; `PimdirRemoteSnapshot` page and resume cursor; scope on the sync call; probes removed from the engine
- [ ] Merge: per-page writes, stamps, deletes inferred at the last page and in scope only
- [ ] Checkpoint keyed by scope; coverage written when a round closes
- [ ] `collect_before`; readers for counts, pages and search
- [ ] Tests on the vectors of 2

## 4. Connectors

- [ ] neverest `imap`: `UID SEARCH SENTSINCE` (a day's margin), pages by UID descending, `ENVELOPE` and `Content-Type`, no `BODYSTRUCTURE`, `CHANGEDSINCE` checked locally
- [ ] neverest `msgraph`: message delta filtered on `receivedDateTime ge since − 2 days`, summary `$select`, 1,000 a page, each page committed; delta link bound to its scope
- [ ] neverest `gmail`: `q=after:<epoch>` with margin, pages, meta from metadata (`Content-Type` among the headers), history checked locally, paced
- [ ] neverest DAV, Google Agenda, People: bodies fetched per page, nothing written unnamed
- [ ] neverest: `item.filter.since` (`30d` or a date), `sync --since`, refused on DAV, Google Agenda and People; coverage and bytes in the report
- [ ] neverest tests: Stalwart (old `Date` received today, future `Date`, none, removal out of scope, widening, interrupted round); live Graph and Gmail
- [ ] Android `imap`, `jmap`, `graph_mail`, `gmail`: the same pages and meta; `PER_MAILBOX` and the windowed spine go
- [ ] Android DAV connectors: bodies per page, as neverest
- [ ] Android `MailEngine.sync`: the probe-then-upgrade step goes; the bound becomes a scope, a narrowed bound a `collect_before`

## 5. Readers

- [ ] himalaya: coverage in `pimdir collection list --json`; the attachment mark as stored
- [ ] MOA: ladder reshaped on paged rounds (`docs/plan/sync-window.md`); coverage in Réglages and in `mail_search`
- [ ] Android: lazy list on counts and pages (`full-mail-index` §3), the bound in Settings

## 6. Land

- [ ] Fold MOA's `sync-window.md` and Android's `full-mail-index` onto this change: what stays theirs, what moved here
- [ ] Status `landed`, log entry
