---
cairn: tasks
change: the-lines-before-v1
---

# The lines, one each

Each open line as `<repo> <change>/tasks.md:<line>, <what> | <class> | <evidence>`, read on 2026-11-19. Ticking a line here means the owner has acted on the class (landed it, or agreed it waits or is obsolete and ticked it in its own folder).

## pimdir

- [ ] pimdir adopt-cairn:10, end the draft relaxation at the freeze | blocks v1 | freeze checklist item 6, cairn/log/2026-11-13-the-freeze-gate-is-rehearsed.md
- [ ] pimdir a-source-names-its-write-guard:8, Annex B.1 guard capabilities | after v1 | its proposal lands it in a STORAGE minor after storage-v1.0.0
- [ ] pimdir a-source-names-its-write-guard:9, SYNC §4 and §5, a connector declaring none | after v1 | same minor
- [ ] pimdir a-source-names-its-write-guard:10, a sync vector, unguarded source | after v1 | a minor may add one vector file (O13)
- [ ] pimdir a-source-names-its-write-guard:11, GUIDE and OVERVIEW, log | after v1 | follows the minor
- [ ] pimdir a-source-names-its-write-guard:12, io-pimdir and neverest follow | after v1 | consumer work of the minor
- [ ] pimdir algorithm-audit-2026-09-04:77, a purge log table | after v1 | decided after v1 as a migration (2026-10-30, edit 7); `store_meta.purges` stands (STORAGE §4.5)
- [ ] pimdir algorithm-audit-2026-09-04:78, a persisted pending bit | after v1 | same decision, D1 of audit-2026-10-31
- [ ] pimdir algorithm-audit-2026-09-04:82, a reader's `?mode=ro` needs the shm | after v1 | one prose sentence, nothing frozen
- [ ] pimdir embedding-index:12, decide the open questions | after v1 | a future part, draft
- [ ] pimdir embedding-index:13, SEARCH §6 chunk boundaries per object hash | obsolete | ticked in search-milestones; `chunk` in migrations/search/0001_init.sql, queries/search/chunks_of.sql
- [ ] pimdir embedding-index:14 to :18, embeddings.db, refresh, fusion, vectors, GUIDE (5 lines) | after v1 | a future part
- [ ] pimdir embedding-index:22 to :25, io-pimdir feature, CLI endpoint, MCP mode, MOA server (4 lines) | after v1 | future consumer work
- [ ] pimdir pim-corpus:8 to :17, name, PRNG, comparator, layers, profiles, m2dir output, seeder, corpora, consumers (10 lines) | after v1 | a tooling project, nothing frozen
- [ ] pimdir pim-corpus:18, move this change out of pimdir | after v1 | decided 2026-10-30 (ledger-housekeeping), not done
- [ ] pimdir performance-audit-2026-11-05:12, tag storage-draft-08, sync-draft-07, search-draft-08 | obsolete | the three tags exist
- [ ] pimdir performance-audit-2026-11-05:15, the phone run on draft-09 stores | obsolete | superseded by the 2026-11-13 phone run (draft-11 store, fill 30 s), write speed closed by the owner that day
- [ ] pimdir performance-audit-2026-11-05:18, the phone's profile after the list-binding fix | obsolete | same closure of 2026-11-13
- [ ] pimdir performance-audit-2026-11-05:19, Android test failing a page write naming a DDL statement | after v1 | an app guard; the 2026-11-13 closure may drop it too
- [ ] pimdir performance-audit-2026-11-05:27, delta and last-page loads by the owing statements | after v1 | deltas load `Owing` (io-pimdir log 2026-11-05-a-delta-loads-what-it-names); the last page needs only an added statement
- [ ] pimdir performance-audit-2026-11-05:28, io-pimdir search planner | after v1 | keyset cursor and per-page sort landed (io-pimdir logs 2026-11-17, 2026-11-18); the rest is implementation speed
- [ ] pimdir performance-audit-2026-11-05:29, SEARCH §8.2 first placement walked, store-order form | after v1 | moves the search part only, which is tagged after storage and sync (Q12); blocks search-v1
- [ ] pimdir performance-audit-2026-11-05:30, Android bridge on the planner | after v1 | app work, android rust/src/search/compile.rs still there
- [ ] pimdir performance-audit-2026-11-05:31, Android lists bound inline per arity | after v1 | app work
- [ ] pimdir performance-audit-2026-11-05:32, the index without `flag` | after v1 | migrations/search/0001_init.sql still holds it; blocks search-v1 only
- [ ] pimdir performance-audit-2026-11-05:33, occurrences bounded by the longest span | after v1 | queries/search/occurrences_between.sql; blocks search-v1 only
- [ ] pimdir performance-audit-2026-11-05:34, coverage once per query | after v1 | implementation speed
- [ ] pimdir performance-audit-2026-11-05:35, Android write-path items | obsolete | write speed closed 2026-11-13, not to be re-proposed
- [ ] pimdir performance-audit-2026-11-05:36 to :38, Android index on a paused fill, LIKE above the cursor, snippets for rows shown (3 lines) | after v1 | app and implementation speed
- [ ] pimdir performance-audit-2026-11-05:49 to :52, owed marker, bounded purge log, unread counters, contentless FTS4 (4 lines) | after v1 | phase 3, only if measured; migrations after v1
- [ ] pimdir the-consumers-gaps-fold-into-draft-08:19, the lone CR stdlib MIME walk in checks/vectors.py | after v1 | a check-script gap, no frozen file
- [ ] pimdir the-consumers-gaps-fold-into-draft-08:20, tags storage-draft-08, sync-draft-07, search-draft-08, gtd-draft-03 | obsolete | the three part tags exist; gtd left the standard (log 2026-10-30-gtd-leaves-the-standard.md)
- [ ] pimdir audit-2026-11-12:46, Y2 | blocks v1 | fake-server tests landed in neverest on 2026-11-19; a real-server run is owed (the owner's grant)
- [ ] pimdir audit-2026-11-12:104, C3 | after v1 | class any; in progress uncommitted in himalaya src/shared/attachment/download.rs, not in pimalaya-cli as the line asks
- [ ] pimdir audit-2026-11-12:106, C5 | after v1 | ruled 2026-11-19 (every recommendation taken); the five hoists landed in io-pimdir the same day (io-pimdir cairn/log/2026-11-19-the-store-rules-the-clis-restate.md); open until himalaya, cardamum and calendula drop their copies, after an io-pimdir release
- [x] pimdir audit-2026-11-12:111, N1 | obsolete | closed 2026-11-19 in its repository (ticked in audit-2026-11-12); was: class any; neverest `DryRunReplica::new` still clones file by file
- [ ] pimdir audit-2026-11-12:112, N2 | after v1 | class any, not re-verified
- [ ] pimdir audit-2026-11-12:120, A5 | after v1 | class after
- [ ] pimdir audit-2026-11-12:121, A6 | after v1 | class after
- [x] pimdir audit-2026-11-12:122, A7 | obsolete | closed 2026-11-19 in its repository (ticked in audit-2026-11-12); was: class any; android PimdirDb.java never reads `synchronous` back on a device
- [x] pimdir audit-2026-11-12:123, A8 | obsolete | closed 2026-11-19 in its repository (ticked in audit-2026-11-12); was: class before; vectors 85, 86, 90, 91, 104, 114, 115 `fails` in android sync-vectors.txt
- [x] pimdir audit-2026-11-12:124, A9 | obsolete | closed 2026-11-19 in its repository (ticked in audit-2026-11-12); was: class before; vector 108 `fails` on Android
- [x] pimdir audit-2026-11-12:125, A10 | obsolete | closed 2026-11-19 in its repository (ticked in audit-2026-11-12); was: class before; vector 49 `fails`, fix uncommitted in android
- [x] pimdir audit-2026-11-12:126, A11 | obsolete | closed 2026-11-19 in its repository (ticked in audit-2026-11-12); was: class before; vector 52 `fails` on Android
- [ ] pimdir audit-2026-10-31:96, pending bit and purge log (D1) | after v1 | decided after v1, a migration
- [ ] pimdir audit-2026-10-31:97, integer surrogate keys (D4) | after v1 | decided not for v1
- [ ] pimdir audit-2026-10-31:105, header and zone derivation, Android follows | after v1 | io-pimdir's half done (b63b39a); Android's is A5
- [ ] pimdir audit-2026-10-31:108, io-pimdir follows the sync-rules log, Android follows | obsolete | io-pimdir and neverest done; A1 closed (android log 2026-11-13-the-store-follows-pimdir-draft-10.md); the revive rule is A9
- [ ] pimdir audit-2026-10-31:112, tags draft-04, draft-05, draft-06, gtd-draft-01, gtd-draft-02 | after v1 | history tags the owner may make; no check reads them
- [ ] pimdir keyset-reads-seek-their-bound:15, io-pimdir re-vendors, Android drops below and unjoined | after v1 | io-pimdir done (b63b39a); android `MailStore.unjoined` remains as an app wrapper
- [ ] pimdir a-refused-push-shows-on-its-receipt:18, neverest and Android classify refusals | obsolete | neverest log 2026-11-15-neverest-follows-draft-13.md (N30), android log 2026-11-16-the-store-follows-pimdir-draft-13.md, both re-checked at draft-14
- [ ] pimdir the-sqlite-floor-is-a-recommendation:17, tags storage-draft-07, search-draft-07, sync-draft-06 | obsolete | the three tags exist
- [ ] pimdir a-narrowed-round-proves-only-what-its-enumeration-lacks:19, consumers hand `enumerated` | obsolete | neverest N27 (log 2026-11-15-neverest-follows-draft-13.md), android log 2026-11-15-a-partial-listing-retires-nothing.md
- [ ] pimdir cross-implementation-vectors:22, Android vendors vectors with a CI re-hash | obsolete | superseded: android CI reads io-pimdir's vendored spec/, io-pimdir checks it against vectors/manifest.json; SyncVectorsTest (a5b5f1e)
- [ ] pimdir collection-role:24, record each backend's role at every sync | obsolete | neverest src/sync/driver/collections.rs `stated_roles`
- [ ] pimdir collection-role:25, a sync declaring every collection, fetching no item | after v1 | no such neverest mode found; consumer work
- [ ] pimdir collection-role:29, himalaya `Mailbox.role` | obsolete | himalaya src/pimdir/backend.rs reads `collection.role`
- [ ] pimdir collection-role:30, calendula and cardamum default | obsolete | both read the role `default` (their src/pimdir/backend.rs)
- [ ] pimdir a-pending-create-is-withdrawn-whatever-the-rights:16, calendula reads item_capabilities | after v1 | "when it next moves"; calendula reads it only for the online-meeting check
- [ ] pimdir capabilities:63, declare sources, collection rows from access rights | after v1 | the rights rows still open in neverest's archived sources-declare-their-capabilities
- [ ] pimdir capabilities:64, the all-mail folder as the archive collection | after v1 | connector work, not found in neverest
- [ ] pimdir capabilities:65, calendar `sendUpdates` | obsolete | neverest src/gcal/client.rs, archived sources-declare-their-capabilities:10
- [ ] pimdir capabilities:66, performer in submit, reply, cancel; online meetings on push | after v1 | reply, cancel, SCHEDULE-AGENT done; online meetings on push open in neverest
- [ ] pimdir capabilities:71, calendula reply and cancel as intents | obsolete | calendula src/pimdir/intent.rs queues `calendar-reply`
- [ ] pimdir capabilities:72, resolve the performer, report ambiguity | obsolete | `NoPerformer`, `AmbiguousPerformer` in himalaya and calendula, `pimdir performer` in himalaya
- [ ] pimdir capabilities:73, MOA shows the partial detail | after v1 | client work
- [ ] pimdir orphan-blobs-are-swept-by-nobody:20, confirm `check --fix` conformant, log it | after v1 | paperwork in io-pimdir
- [ ] pimdir round-head:38, live heads on the mail test boxes | after v1 | live tests, the owner's grant
- [ ] pimdir round-head:42, MOA: arrival during a first sync | after v1 | client check
- [ ] pimdir round-head:43, Android heads in its connectors | after v1 | app work
- [ ] pimdir scoped-mail-sync:12 to :17, timings, token lifetime, reads per second, inserts over JNI, page sizes (5 lines) | after v1 | measurements
- [ ] pimdir scoped-mail-sync:28, daily quota and download cap | after v1 | connector work
- [ ] pimdir scoped-mail-sync:59, neverest live widening tests | obsolete | widening validated live 2026-11-15 (.github cairn/changes/live-testing-2026-11-15/reports/summary.md, neverest efc2cb3); whether the named test ran is unsure
- [ ] pimdir storage-draft-09:21, tags storage-draft-09, sync-draft-08, search-draft-09 | after v1 | history tags the owner may make
- [ ] pimdir storage-draft-09:25, io-pimdir re-vendors, CI pin | obsolete | io-pimdir follows draft-14 (v0.17.0), checks/io-pimdir.rev pins it
- [ ] pimdir storage-draft-09:26, Android shape forks, phone run | obsolete | android follows draft-14 (ac77efe), phone run 2026-11-13
- [ ] pimdir storage-draft-09:27, the four CLIs pinned | obsolete | all on io-pimdir 0.17.0
- [ ] pimdir search-milestones:21, SEARCH leaves draft once io-pimdir answers every case | after v1 | the search-v1 release, after storage and sync
- [ ] pimdir search-milestones:25, io-pimdir M1 to M3 | obsolete | io-pimdir logs 2026-10-27-search-index-m1 to m3
- [ ] pimdir search-milestones:26, M4 tag and thread | obsolete | io-pimdir log 2026-10-27-search-index-m4.md
- [ ] pimdir search-milestones:27, targets at 1M | after v1 | 50k measured (io-pimdir log 2026-10-30-a-search-answers-at-scale.md), 1M p95 not
- [ ] pimdir search-milestones:28, consumers on the library | after v1 | the three CLIs on io-pimdir 0.17; pimalaya-linux on the pre-fold io-pimdir
- [ ] pimdir search-milestones:29, the tz database version exposed | obsolete | ical log 2026-10-27-tzdb-pinned-and-versioned.md, io-pimdir src/search/refresh.rs `tzdb_version`
- [ ] pimdir no-write-collects:14, the Android collector | obsolete | android MailStore.java `collectGarbage`, PimdirBlobs.java
- [ ] pimdir two-silent-losses-fold-into-draft-08:15, a producer waits on a failing file | after v1 | liveness, not a loss; STORAGE §5 unchanged
- [x] pimdir two-silent-losses-fold-into-draft-08:16, a sync vector stating a file with no row | landed | ruled 2026-11-19 before the draft-14 tags: `row` on a sync object, format 8, vector 172 (cairn/log/2026-11-19-a-file-with-no-row.md); no draft bump, the parts being untagged

## io-pimdir

- [ ] io-pimdir a-conflict-never-hides-a-server-edit:16, neverest picks it up | obsolete | neverest on io-pimdir 0.17.0
- [ ] io-pimdir a-delta-loads-what-it-names:12, a round's last page keeps `All` | after v1 | speed; an added count statement
- [ ] io-pimdir a-delta-loads-what-it-names:14, bench a step into 100k and 1M | after v1 | measurement; write speed closed 2026-11-13
- [x] io-pimdir a-page-lands-in-few-statements:12, :14, :26, device run and numbers | obsolete | the 2026-11-13 phone run and the owner's closure; ticked there 2026-11-19, the change abandoned
- [x] io-pimdir a-page-lands-in-few-statements:18 to :20, the pending stamp in pimdir, io-pimdir and Android | obsolete | the pending stamp left the format (pimdir log 2026-11-05-storage-draft-09.md); ticked there 2026-11-19, the change abandoned
- [x] io-pimdir a-page-lands-in-few-statements:24, :27, the sender rule once a page, a chunked lookup | obsolete | not to be re-proposed (2026-11-13); ticked there 2026-11-19, the change abandoned
- [x] io-pimdir a-page-lands-in-few-statements:31, fold, log, CHANGELOG | obsolete | the change closed as abandoned 2026-11-19, its delta never folded
- [ ] io-pimdir an-owner-write-checks-its-fence:7 to :11 (5 lines) | after v1 | ruled 2026-11-19: option (a), a storage-v1 minor adding a `store_meta` column, Android exempt; the change active and deferred
- [ ] io-pimdir charset-tables-for-legacy-cjk:13, neverest enables the feature | obsolete | the feature was removed, encoding_rs a plain dependency (log 2026-11-13-the-crate-follows-draft-10-payloads-and-identity.md)
- [ ] io-pimdir a-refused-push-shows-on-its-receipt:11, spec/REVISION | obsolete | spec/REVISION at da7e01a
- [ ] io-pimdir a-refused-push-shows-on-its-receipt:12, neverest and Android answer `Refused` | obsolete | neverest src/sync/remote.rs, android rust/src/offline.rs build `PimdirPushOutcome::Refused`
- [ ] io-pimdir a-page-sorts-its-own-hits:11, the threads' statement per hit | after v1 | search speed, an added statement
- [x] io-pimdir an-ambiguous-intent-awaits-confirmation:6 to :12 (7 lines) | obsolete | landed through pimdir O7 and F16: `unconfirm_action`, `retry_action` (src/client.rs), `PimdirActionStatus::Unconfirmed`, `queue retry`, tests/queue_text.rs, neverest src/sync/submit.rs; the change landed 2026-11-19 (io-pimdir cairn/log/2026-11-19-an-ambiguous-intent-awaits-confirmation.md)
- [ ] io-pimdir raw-payloads-print-their-length:6 to :9 (4 lines) | after v1 | log privacy and API, no format effect
- [ ] io-pimdir a-pending-create-is-withdrawn-whatever-the-rights:14, calendula reads item_capabilities | obsolete | nothing to change: calendula reads it only for online meetings
- [ ] io-pimdir one-refusal-for-another-version:12, the three CLIs show it | after v1 | calendula and cardamum done 2026-11-18; himalaya pending per its session (himalaya src/error.rs already names `PimdirFormatRefusal`), to confirm there
- [ ] io-pimdir derivation-before-the-write:6 to :10 (5 lines) | after v1 | writer-lock hold time, internal
- [ ] io-pimdir an-in-memory-card-matcher:12, cardamum calls it | obsolete | cardamum src/shared/card/search.rs calls `match_cards`
- [ ] io-pimdir deep-mime-regression:6 to :8 (3 lines) | after v1 | a test generator only; the fix landed (189db40)
- [ ] io-pimdir a-push-reads-back-the-server-bytes:7 to :13 (7 lines) | after v1 | ruled 2026-11-19: after v1, an additive optional body on the push outcome; the change active and deferred
- [ ] io-pimdir the-crate-follows-storage-draft-08:87, `coverage` and `match_objects_ranked` | obsolete | `coverage` landed; `match_objects_ranked` cut (pimdir F10)
- [ ] io-pimdir the-crate-follows-storage-draft-08:107 to :111 (5 lines), pimdir ticks, CI pin, neverest, himalaya, Android | obsolete | pimdir CI `implementation` job; every consumer on io-pimdir 0.17.0 and draft-14
- [ ] io-pimdir an-io-free-indexer:8, review the yields with the owner | after v1 | crate API, not format
- [ ] io-pimdir search-feature:41, SEARCH §8.2 temporal axis | obsolete | SEARCH.md "Coverage has a temporal axis", vectors/search/queries.json
- [ ] io-pimdir search-feature:42, consumers say what a search covered | after v1 | consumer UI
- [ ] io-pimdir search-feature:48 to :50 (3 lines), folds, own statements, typed outputs | after v1 | ledger and API comfort
- [x] io-pimdir the-default-enqueue-strips:11, calendula's online-meeting path | obsolete | calendula src/pimdir/backend.rs routes `ItemOrigin::User` to `enqueue_user_body` (ticked there 2026-11-19)
- [ ] io-pimdir one-no-replace-move:9, Android moves through `PimdirBlobMove` | after v1 | app work (2026-11-19)
- [ ] io-pimdir a-purge-of-chosen-items:9, neverest calls `purge_items` | after v1 | neverest work (2026-11-19)
- [ ] io-pimdir the-store-rules-the-clis-restate:9, the CLIs drop their copies | after v1 | lines 6 to 8 ticked 2026-11-19 (ruling, hoists, fold); their sessions, after an io-pimdir release

## Found on 2026-11-19

- [ ] io-pimdir a-purge-of-chosen-items:10, an account-scoped batch purge (neverest's ask, P5) | after v1 | additive in io-pimdir, or a sibling statement in a storage minor
- [ ] io-pimdir, a public in-flight guard on `PimdirSourceStore` (neverest's ask, audit N2) | after v1 | additive; recorded on audit-2026-11-12 N2
- [ ] io-pimdir the-merge-verdict-is-public:9, the Android app reads `PimdirHubItem::reconcile` | after v1 | app work, the public verdict landed 2026-11-19
