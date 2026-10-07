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

- [x] neverest `msgraph`: `date` from `sentDateTime` (`message_date`) (neverest 15c4acc)
- [x] Android `graph_mail`: the same; `sentDateTime` in `MESSAGE_SELECT` (android c2782a8)
- [ ] io-msgraph: a way to send `Prefer: odata.maxpagesize`; neverest and the Android bridge send 1,000 on message delta, with the summary `$select` (io-msgraph 00ef069; neverest 2b59f13 sends it with every link)
- [x] neverest `imap`: `delete_message` by `UID EXPUNGE` on the one UID, the push rejected on a server with neither UIDPLUS nor IMAP4rev2 (neverest a044e91)
- [x] neverest: `Retry-After`, back-off on 429, 503 and Gmail quota errors, `throttled { source, until }` in the report (neverest 3d94aed; a create retried on 429 only, Graph 5xx batch bodies no throttle: 2b59f13)
- [x] Android bridge: the same back-off (android c2782a8)
- [ ] neverest and the Android bridge: Gmail paced near 40 reads a second, below the 250-unit quota (neverest 3d94aed)

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

- [x] Re-vendor schema and statements; reconcile on open
- [x] `PimdirRemoteItem` carries link id, summary and sort key; `PimdirRemoteSnapshot` page and resume cursor; scope on the sync call; probes removed from the engine
- [x] Merge: per-page writes, stamps, deletes inferred at the last page and in scope only
- [x] Checkpoint keyed by scope; coverage written when a round closes
- [x] `collect_before`; readers for counts, pages and search
- [x] Tests on the vectors of 2

## 4. Connectors

- [x] neverest `imap`: `UID SEARCH SENTSINCE` (a day's margin), pages by UID descending, `ENVELOPE` and `Content-Type`, no `BODYSTRUCTURE`, `CHANGEDSINCE` checked locally (neverest 2b59f13; the header fields carry what `ENVELOPE` does, read as the body is, so no `ENVELOPE`; undated mail searched apart)
- [x] neverest `msgraph`: message delta filtered on `receivedDateTime ge since − 2 days`, summary `$select`, 1,000 a page, each page committed; delta link bound to its scope (neverest 2b59f13)
- [x] neverest `gmail`: `q=after:<epoch>` with margin, pages, meta from metadata (`Content-Type` among the headers), history checked locally, paced (neverest 2b59f13; one paced read per id, io-gmail having no batch)
- [x] neverest DAV, Google Agenda, People: bodies fetched per page, nothing written unnamed (neverest 2b59f13: new or changed members read 64 at a time, Graph contacts and events too)
- [x] neverest: `item.filter.since` (`30d` or a date), `sync --since`, refused on DAV, Google Agenda and People; coverage and bytes in the report (neverest 2b59f13: `coverage`, `downloaded`)
- [ ] neverest tests: Stalwart (old `Date` received today, future `Date`, none, removal out of scope, widening, interrupted round); live Graph and Gmail (Stalwart done, neverest 2b59f13 tests/scope.rs; live Graph and Gmail compile, not run)
- [x] Android `imap`, `jmap`, `graph_mail`, `gmail`: the same pages and meta; `PER_MAILBOX` and the windowed spine go (android 57e44ed; Gmail metadata one paced read per id, io-gmail having no batch)
- [x] Android DAV connectors: bodies per page, as neverest (android 57e44ed: new or changed members read 64 at a time)
- [x] Android `MailEngine.sync`: the probe-then-upgrade step goes; the bound becomes a scope, a narrowed bound a `collect_before` (android 57e44ed)

## 5. Readers

- [ ] himalaya: coverage in `pimdir collection list --json`; the attachment mark as stored
- [ ] MOA: ladder reshaped on paged rounds (`docs/plan/sync-window.md`); coverage in Réglages and in `mail_search`
- [x] Android: lazy list on counts and pages (`full-mail-index` §3), the bound in Settings (android 57e44ed)

## 6. Land

- [ ] Fold MOA's `sync-window.md` and Android's `full-mail-index` onto this change: what stays theirs, what moved here
- [ ] Status `landed`, log entry
