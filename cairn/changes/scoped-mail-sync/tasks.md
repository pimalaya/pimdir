---
cairn: tasks
change: scoped-mail-sync
---

# Tasks

Ordered: each block needs the ones above it, except 1, which can start at once.

## 0. Measure (test accounts only, never a real box)

- [ ] IMAP: Stalwart or Dovecot seeded with ~100k synthetic mails; time `UID FETCH (UID FLAGS INTERNALDATE ENVELOPE)` with `BODY.PEEK[HEADER.FIELDS (CONTENT-TYPE)]`, against `BODYSTRUCTURE` (not done: neverest's Stalwart tests stop at 1,600 mails)
- [x] Graph, on MOA's test tenant: `$deltatoken=latest` ignored, message delta newest first, summary `$select` at 1,000 a page (proposal, measured 2026-10-07; the 1,000 was wrong, Graph answers message delta in pages of 512 at that ask, moa a1d4ba0 docs/plan/findings.md)
- [ ] Graph: skip token lifetime, for resuming an interrupted round (not measured; an expired link or cursor restarts the round, neverest 3938d10, android 0bebef8)
- [ ] Gmail: metadata reads per second when paced near 40, batched (not measured; io-gmail has no batch, so both clients read one paced id at a time)
- [ ] Store: inserts per write at 1k, 2k and 5k rows, natively and over JNI (not done as asked: Android timed one 4,000-message round on the host, store 1.2 s down to 1.0 s, android 7bb0e68 docs/performance.md; nothing over JNI on a device)
- [ ] Record in android docs/performance.md and moa docs/plan/findings.md; confirm or lower the default page sizes (proposal §2) (partly: moa findings.md records Graph's 512, moa a1d4ba0; the other page sizes neither confirmed nor lowered)

## 1. Fixes with no spec change

- [x] neverest `msgraph`: `date` from `sentDateTime` (`message_date`) (neverest 15c4acc)
- [x] Android `graph_mail`: the same; `sentDateTime` in `MESSAGE_SELECT` (android c2782a8)
- [x] io-msgraph: a way to send `Prefer: odata.maxpagesize`; neverest and the Android bridge send 1,000 on message delta, with the summary `$select` (io-msgraph 41922fb, 00ef069; neverest 2b59f13 sends it with every link; android 57e44ed; Graph caps the page at 512)
- [x] neverest `imap`: `delete_message` by `UID EXPUNGE` on the one UID, the push rejected on a server with neither UIDPLUS nor IMAP4rev2 (neverest a044e91)
- [x] neverest: `Retry-After`, back-off on 429, 503 and Gmail quota errors, `throttled { source, until }` in the report (neverest 3d94aed; a create retried on 429 only, Graph 5xx batch bodies no throttle: 2b59f13)
- [x] Android bridge: the same back-off (android c2782a8)
- [x] neverest and the Android bridge: Gmail paced near 40 reads a second, below the 250-unit quota (neverest 3d94aed: 200 units a second; android c2782a8: 40 requests a second)
- [ ] Gmail's daily quota and the IMAP daily download cap accounted across runs (not done: only the per-second pace is held)

## 2. pimdir (this repository)

- [x] SYNC.md §4: paged enumeration (page, resume cursor, last page), every member named with its meta (a2e92af)
- [x] SYNC.md §5: scope (in-scope rule, two-day margin, absence only in scope, explicit removals always, local changes always), rounds stamped and closed, checkpoint bound to its scope (a2e92af; a band round infers no delete of an undated member, 00535c1)
- [x] SYNC.md §3, §5, §6, §12: probes and `Probed` removed; creates wait for the page that lands them; naming at enumeration on §6's identity rules (a2e92af)
- [x] STORAGE.md: coverage and the open round per `(collection, source)`; the round stamp on bindings; `collect_before`; the `probes` table and its statements removed (a2e92af; `sources.round_band`, 00535c1)
- [x] Annex A: the attachment mark without the body (the source's flag, else `multipart/mixed`), replaced by the walk of the parts (a2e92af)
- [x] migrations/storage: coverage, round and stamp columns; `probes` dropped (level 0 rows read as meta to revisit); queries: `set_coverage`, `collect_before`, `count_mail`, per-day and unread counts, sender and subject `LIKE` (a2e92af)
- [x] vectors: a paged round (interrupted, resumed, restarted), an old `Date` received today, a future `Date`, no `Date`, an explicit removal out of scope, a widening, a collection, a create landed by a page, the attachment mark both ways; in every one, no `Remove` pushed that the consumer did not stage (a2e92af: 34 to 45; 00535c1: 46, 47)
- [x] checks/invariants.sh; GUIDE.md, OVERVIEW.md (a2e92af, 00535c1)
- [x] log entry (cairn/log/2026-10-07-scoped-mail-sync.md)

## 3. io-pimdir

- [x] Re-vendor schema and statements; reconcile on open (io-pimdir 35a1c3f)
- [x] `PimdirRemoteItem` carries link id, summary and sort key; `PimdirRemoteSnapshot` page and resume cursor; scope on the sync call; probes removed from the engine (io-pimdir 35a1c3f)
- [x] Merge: per-page writes, stamps, deletes inferred at the last page and in scope only (io-pimdir 35a1c3f; an empty date stored as `NULL`, f9b13f8; a band round keeps undated mail, ff28408)
- [x] Checkpoint keyed by scope; coverage written when a round closes (io-pimdir 35a1c3f)
- [x] `collect_before`; readers for counts, pages and search (io-pimdir 35a1c3f)
- [x] Tests on the vectors of 2 (io-pimdir 35a1c3f, f9b13f8, ff28408)

## 4. Connectors

- [x] neverest `imap`: `UID SEARCH SENTSINCE` (a day's margin), pages by UID descending, `ENVELOPE` and `Content-Type`, no `BODYSTRUCTURE`, `CHANGEDSINCE` checked locally (neverest 2b59f13; the header fields carry what `ENVELOPE` does, read as the body is, so no `ENVELOPE`; undated mail searched apart)
- [x] neverest `msgraph`: message delta filtered on `receivedDateTime ge since − 2 days`, summary `$select`, 1,000 a page, each page committed; delta link bound to its scope (neverest 2b59f13; replaced by neverest 3938d10: one unfiltered delta link per folder, a scope listed by band on `sentDateTime`, bound to no scope)
- [x] neverest `gmail`: `q=after:<epoch>` with margin, pages, meta from metadata (`Content-Type` among the headers), history checked locally, paced (neverest 2b59f13; one paced read per id, io-gmail having no batch)
- [x] neverest DAV, Google Agenda, People: bodies fetched per page, nothing written unnamed (neverest 2b59f13: new or changed members read 64 at a time, Graph contacts and events too)
- [x] neverest: `item.filter.since` (`30d` or a date), `sync --since`, refused on DAV, Google Agenda and People; coverage and bytes in the report (neverest 2b59f13: `coverage`, `downloaded`)
- [x] neverest: a landed page's bodies download while the next pages list (neverest 6f9017c); the band round's undated workaround removed on io-pimdir ff28408 (neverest 9ebf608); specs folded (neverest 010940c, 47e094c, 4a3427a, f7a47fa, b3d65bb)
- [ ] neverest tests: Stalwart (old `Date` received today, future `Date`, none, removal out of scope, widening, interrupted round); live Graph and Gmail (Stalwart done, neverest 2b59f13 tests/scope.rs, 6f9017c, 9ebf608; live Graph and Gmail compile, `a_graph_scope_widens_by_its_band` among them, not run: the band listings of 3938d10 and android 0bebef8 are validated on no live tenant or Gmail box)
- [x] Android `imap`, `jmap`, `graph_mail`, `gmail`: the same pages and meta; `PER_MAILBOX` and the windowed spine go (android 57e44ed; Gmail metadata one paced read per id, io-gmail having no batch; Graph one unfiltered delta link, mail listed by band, 0bebef8; undated mail kept on a band, eacb71e; nothing run on a device or a live tenant)
- [x] Android DAV connectors: bodies per page, as neverest (android 57e44ed: new or changed members read 64 at a time)
- [x] Android `MailEngine.sync`: the probe-then-upgrade step goes; the bound becomes a scope, a narrowed bound a `collect_before` (android 57e44ed; a short first sync by chunks of 50, widened by count, 7bb0e68)

## 5. Readers

- [x] himalaya: coverage in `pimdir collection list --json`; the attachment mark as stored (himalaya 32d2876, as `pimdir mailbox list`; envelope pages read by keyset, 065e7e4; io-pimdir pins e431a7b, e71e9cb; calendula 3443391, 7458a28, d6f068d and cardamum 296a734, 237be41, a0ddf12 pinned alike)
- [x] MOA: ladder reshaped on paged rounds (`docs/plan/sync-window.md`); coverage in Réglages and in `mail_search` (moa ca77922 pins, f187373: no ladder, Inbox and Sent first kept, exit 3 on an open round resumes the first sync, coverage from `himalaya pimdir mailbox list` in Réglages and as a note on the agent's `mail_search`; measured in moa docs/plan/findings.md, a1d4ba0; a box shown while it fills, 8dbb84a to 8a90209)
- [x] Android: lazy list on counts and pages (`full-mail-index` §3), the bound in Settings (android 57e44ed, 7bb0e68)

## 6. Land

- [x] Fold MOA's `sync-window.md` and Android's `full-mail-index` onto this change: what stays theirs, what moved here (moa a1d4ba0: sync-window.md superseded by this change; android `full-mail-index` landed and archived, 57e44ed)
- [x] Status `landed`, log entry
