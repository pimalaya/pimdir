---
cairn: tasks
change: the-freeze-plan
---

# Tasks

## 1. Y2

- [x] neverest: an integration test starting maddy (nixpkgs) on loopback when its binary is given, checking first that its CAPABILITY lacks UIDPLUS
- [x] Case a: a remove into a mailbox already holding the same `Message-ID` is held, nothing copied nor marked `\Deleted`, gated on `if_match`; again with a stale `if_match`
- [x] Case b: an append answered with no `APPENDUID` is bound by `UID SEARCH HEADER Message-ID`, one copy, a second run changing nothing
- [x] maddy in neverest's flake, the test in its CI; tick audit-2026-11-12/tasks.md:46

## 2. The generator

- [x] D1 decided (2026-11-20, a Rust crate here); pim-corpus's name, PRNG and manifest format settled with it
- [x] The model: accounts, sources, collections, the four kinds, the structure cases of pim-corpus/proposal.md enumerated
- [x] The scenario catalogue, read from himalaya, cardamum, calendula, neverest and the Android app: every queued action each issues, every sync sequence neverest runs
- [x] The writer: a store from the canonical statements of queries/ alone, checked by checks/schema.sh's rules
- [x] The scripted remote states, for scripted connectors
- [x] The oracle: reads, counts, overlay, change feed, engine runs
- [x] The oracle: search answers (io-pimdir spec/generator/src/query.rs, cairn/log/2026-11-25-the-oracle-answers-search.md; following search-draft-19, cairn/log/2026-11-25-the-oracle-follows-search-draft-19.md)
- [ ] Shrinking: a failing seed reduced and written as a vector
- [x] Profiles: structure, count (100k items), bytes (large bodies)
- [ ] Profile: quirks
- [x] Its own checks in `nix flake check`

## 3. io-pimdir's differential tests

- [x] Readers against the oracle on generated stores, queued rows of every producer included
- [x] The engine replaying generated scripts through scripted connectors: no loss, convergence, queue order
- [x] A crash injected at every step of a replay, the store reopened and the run finished
- [x] The search index refreshed after each event equal to a rebuild
- [x] The count and bytes profiles under the scale tests (debug sizes; the full sizes, release only, not yet run to the end)

## 4. The seams in the standard

- [x] Vectors of a refresh driven by the change feed (STORAGE §4.5): stamps after each kind of write, a summary row changed under an unchanged item, a rename, a purge, an erasure
- [x] Every SHOULD and MAY of STORAGE, SYNC and SEARCH listed with the consumers relying on it; each promoted, documented or kept with a reason
- [x] The overlay of STORAGE:961 decided among them

## 5. Owner decisions

- [x] D2 decided (2026-11-20): in sync-v1
- [x] D2 landed: SYNC text, vectors 174 and 175, io-pimdir (neverest mapping waits for an io-pimdir release)
- [x] D3 decided (2026-11-20): search inside io-pimdir 1.0, SEARCH released with the other parts
- [x] D4 decided (2026-11-20): outside
- [x] D4 stated in the `pimdir` binary's help and README
- [x] D4 amended (2026-11-21): outside but for the JSON output io-pimdir's the-json-output-is-the-integration-point names, stated in the binary's help and README, pinned by io-pimdir tests/json_contract.rs
- [x] D5 decided (2026-11-20): two campaigns in a row with no spec break

## 5b. Search in v1

- [x] README.md, every Status line and AGENTS.md: the three parts release together
- [x] The query language reviewed once: grammar, every form and every refusal listed, each refusal coded (2026-11-25, cairn/log/2026-11-25-the-search-lines-close-for-the-freeze.md: the inventory's forms and refusals as 51 cases of vectors/search/queries.json, `thread:`, `dangling-operator`, `linked:<role>:` and the empty value reworded)
- [x] Query vectors: every form of the grammar, run over generator stores, not one fixed store (io-pimdir tests/generated/search.rs, cairn/log/2026-11-25-the-oracle-answers-search.md; what a hit `matched` compared there since cairn/log/2026-11-25-the-oracle-follows-search-draft-19.md)
- [x] Extraction vectors per kind: MIME parts, charsets, attachments; vCard fields; iCalendar fields, time zones, all-day items, recurrence expansion up to its bound; Unicode normalisation and case (2026-11-25, vectors/search/extraction.json, the bounds staying in store.json's series)
- [x] Threads, snippets and coverage (`complete`, `filling`, `missing`) pinned by vectors (2026-11-25: threads in refresh.json and queries.json, snippets informative in SEARCH §6, `complete` on six more cases, `matched`, `unparseable` in extraction.json)
- [x] A page token stays valid, or is refused coded, across a refresh between two pages (2026-11-25: a cursor is a position, SEARCH §8.2, five page cases of refresh.json; a token a client cannot read is its own to refuse, under no SEARCH code)
- [x] The generator's oracle answers every search the vectors ask (2026-11-25: the 353 cases of queries.json, refusal spans and `matched` included, and the 83 queries of extraction.json, none disagreeing; refresh.json is not asked, the model following no owner write of it; cairn/log/2026-11-25-the-oracle-follows-search-draft-19.md)
- [x] io-pimdir G27, a calendar item holding no body dated by its sort key: SEARCH §7 now says it yields no occurrence, io-pimdir follows (search-draft-19, extraction.json "a calendar item holding no body")
- [ ] Owner ruling on io-pimdir G28: a series every rule of which ends on a day before its `DTSTART` occurs at its `DTSTART` (RFC 5545 §3.8.5.3) or never (ical-rs, io-pimdir: the shape of a series deleted from its first instance on); SEARCH §7 says neither (cairn/log/2026-11-25-the-oracle-follows-search-draft-19.md)
- [x] The freeze checklist gains `search-v1.0.0`; checks/frozen.sha256 the search statements and signatures (2026-11-25: checks/frozen.sha256's header names the search-v1.0.0 block, checks/appended.py holds the case lists to a prefix; the statements and signatures are obsolete since 2026-11-22, the standard binding none, cairn/log/2026-11-22-a-smaller-pimdir.md)

## 6. io-pimdir's public API

- [x] The list of public items, each kept, made private or removed (io-pimdir 55d2702, its CHANGELOG Unreleased and cairn/log/2026-11-25-the-public-api-for-one-zero.md)
- [x] `#[non_exhaustive]` on the enums consumers match and on nothing else, the family rule of 2026-11-21 barring it to keep an API growable: `PimdirError`, `PimdirSyncEvent`, `PimdirEnumerated`, `PimdirWaitReason`, `PimdirQueryErrorCode`; removed from `PimdirPushOutcome`; structs stay pub-fielded (io-pimdir cairn/spec/store.md, "The enums consumers match grow without a major")
- [x] `PimdirReader::pending_actions` lists a row whose payload it cannot decode (done before, io-pimdir cairn/spec/store.md); `pending_arrivals` now does the same (io-pimdir tests/queue.rs `a_malformed_arrival_is_listed_opaque`, failing on 769dfba)
- [x] An owner write registering a source with no checkpoint: `PimdirSourceStore::register` (io-pimdir 55d2702); neverest replaces src/sync/storage.rs:143-182 with it at its next move
- [x] Private fields behind a constructor where a value must be guarded: `for_source` refuses an empty source id as `source-empty`; structs stay pub-fielded, built as literals
- [x] Every public item documented and named by the family's rules (`deny(missing_docs)`, no provider names in docs, `Chunks` and `load::PimdirRefusal` renamed, no re-exports)
- [x] The MSRV stated (1.89: base64-codec and quoted-printable-codec need it, `client` alone builds on 1.88) and the features checked (CI msrv job and the consumers' feature sets)
- [x] `cargo semver-checks` in CI, baseline 1.0.0, running once 1.0.0 is on crates.io

## 7. Campaigns

- [ ] The campaign's seeds and profiles fixed and recorded
- [ ] Campaign 1 run, each finding sorted by door, the failures shrunk into vectors
- [ ] Campaign 2 run; the stop rule met, or another campaign

## 8. Release mechanics

- [x] pimalaya/nix release workflow: refuse a tag whose version is not the crate's; mark a tag holding `-` a pre-release
- [ ] The freeze checklist of cairn/log/2026-11-13-the-freeze-gate-is-rehearsed.md read against the current drafts (search-draft-14)
- [ ] io-pimdir passing the tree to freeze, tests/pending_vectors.txt empty, checks/io-pimdir.rev naming it
- [ ] Ready: the owner runs the freeze commit and the tags

## Left on 2026-11-20

Where the work stopped, for the next session. Every lane's findings are in cairn/log/ (entries of 2026-11-20) and in io-pimdir's tests/generated (`known()` lists and `#[ignore]` reasons).

- [ ] Plan 5b, all but the release wording: the query language review and grammar-form coverage check, extraction vectors per kind, threads/snippets/coverage vectors, page tokens across a refresh (rule decided: a cursor names a position, sort key and seq)
- [ ] Two readings to pin: a mutable revival whose member carries another body keeps the old one (vector 108 covers the bodiless case alone); a fill settling an item conflict takes the adopted body's summary (vectors 114, 115 to state it). 2026-11-25: the fill's summary pinned by 114 and 115; the revival left for the owner, STORAGE §11.1 reading the other way and io-pimdir releasing the old body (cairn/log/2026-11-25-the-engine-findings-close-for-the-freeze.md)
- [x] The generator follows G15 (seq order, STORAGE §9.1) and SYNC §5's next-run debt; then the replay's known findings G14 to G17 are lifted in io-pimdir tests/generated (2026-11-25: the generator draws a kept body's seq after the write's upserts, the debt already withheld; io-pimdir fixed G12 with vector 232; the replay's known findings and its ignored twin are gone, cairn/log/2026-11-25-the-engine-findings-close-for-the-freeze.md)
- [x] Generator readings G18 (a move or copy out of an unsynced collection parks) and G19 (a move of a bodiless based item passes) (2026-11-25: io-pimdir spec/generator/src/queue.rs `apply_copy` follows STORAGE §15.3 and SYNC §7 on both, the scale test's own park and bodiless exclusion gone)
- [x] io-pimdir G20: `retained_by` of a removed item no source binds; G21: the oracle and automatic `sender` references (a MAY) (2026-11-25: io-pimdir leaves `retained_by` NULL, tests/unbound_items.rs failing before; the scale test accepts the `sender` rule's references, every one the rule states from a mail, or none)
- [ ] G29, for the owner: STORAGE §11.4 releases `base_object` alone, §5 pins `shared_object` past the item's body, §14 releases both "as §11.4 releases one"; io-pimdir clears both, the generator the base alone (cairn/log/2026-11-25-the-engine-findings-close-for-the-freeze.md proposes §11.4 naming both, storage-draft-19)
- [ ] The full-size count profile rerun in release with the collection hierarchy (bytes passes)
- [ ] The flaky crash failure seen once in five runs: not reproduced in 13 runs, likely a half-edited tree; watch for it
- [x] ical-rs release with the bounded zone walk (ical a125d24), io-pimdir on it with `EXTRACTOR` moved, the hostile-zone search case out of tests/pending_vectors.txt (checks/implementation.sh is red until then)
- [x] Consumers after an io-pimdir release (io-pimdir 0.19.0, 2026-11-20; Android Java side left to its session): neverest maps one-way to `KeepLocal`; cardamum and calendula pass no `hash:` key and use `PimdirEnqueued::link_id`; Android follows `PimdirWritten`, `PimdirRekeyReport`, `PimdirLoaded::folded` and may use the canonical collection statements
- [x] Owner decisions of 2026-11-25: `KeepLocal` stays content-only; a copy or a move stages its target's create under a source syncing the target, the run's where it syncs it, else the one an `add` there runs as, and is refused where none does; a stated `alt:` key stays unchecked; the `pimdir` binary's schema `$id` names the major from 1.0; the attachments collection id is a MUST (cairn/log/2026-11-25-five-freeze-decisions.md, storage-draft-18, sync-draft-16, search-draft-18)
- [x] Owner decision of 2026-11-25: a narrowed round's `enumerated` stays a SHOULD for a connector offering an enumeration (SYNC §4, §5; cairn/log/2026-11-20-the-shoulds-and-mays-reviewed.md), no text moving
- [ ] Sections 6 (API review), 7 (campaigns) and 8 (freeze checklist) not started
- [x] The replay harness gains cuts, head answers and rekey so the rekeys, crashes, heads and bodies histories replay through io-pimdir (io-pimdir 5d6419a, 2026-11-21: three summary bugs fixed in rekey, upgrade and hub; bodies 4, 9, 14 are G25, 26 clean, 33 a harness artefact)
- [x] Owner decision G23: does a rekey run the flag axis on the flags its listing states (SYNC §8 "carries each placement's flags, base"; io-pimdir merges them, the generator keeps them): decided 2026-11-21, yes, io-pimdir's reading, stated in SYNC §8 with vector 195 (cairn/log/2026-11-21-a-rekey-runs-the-flag-axis.md)
- [x] The generator follows SYNC on G24 (a rekey's pull takes the member's summary), G25 (an upgrade reports no `Conflicted`), G26 (a bodiless revival leaves `shared_object`, STORAGE §10) and the turned-over G14 (a folded body owed is the collection's divergence); then lift them in io-pimdir tests/generated: done 2026-11-21, the generator follows the spec on all five and io-pimdir's replay runs clean of them (same log entry; io-pimdir cairn/log/2026-11-21-the-replay-findings-lifted.md)
- [x] The other io-* crates move to cargo-006's client, server and std features (released 2026-11-21: io-http 0.9.0, io-oauth 0.8.0, io-webdav 0.13.0, io-gcal 0.6.0, io-gmail 0.10.0, io-gpeople 0.9.0, io-gtasks 0.3.0, io-msgraph 0.10.0, io-jmap 0.11.0, io-managesieve 0.6.0, io-pim-discovery 0.15.0, io-proxy 0.3.0; apps moved)
