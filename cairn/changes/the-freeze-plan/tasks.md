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
- [ ] The oracle: search answers
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
- [x] D5 decided (2026-11-20): two campaigns in a row with no spec break

## 5b. Search in v1

- [x] README.md, every Status line and AGENTS.md: the three parts release together
- [ ] The query language reviewed once: grammar, every form and every refusal listed, each refusal coded
- [ ] Query vectors: every form of the grammar, run over generator stores, not one fixed store
- [ ] Extraction vectors per kind: MIME parts, charsets, attachments; vCard fields; iCalendar fields, time zones, all-day items, recurrence expansion up to its bound; Unicode normalisation and case
- [ ] Threads, snippets and coverage (`complete`, `filling`, `missing`) pinned by vectors
- [ ] A page token stays valid, or is refused coded, across a refresh between two pages
- [ ] The generator's oracle answers every search the vectors ask
- [ ] The freeze checklist gains `search-v1.0.0`; checks/frozen.sha256 the search statements and signatures

## 6. io-pimdir's public API

- [ ] The list of public items, each kept, made private or removed
- [ ] `non_exhaustive` on every enum and struct expected to grow (`PimdirConflictPolicy` among them)
- [ ] `PimdirReader::pending_actions` lists a row whose payload it cannot decode instead of failing the listing (STORAGE §15.4; finding G1 of io-pimdir tests/generated)
- [ ] An owner write registering a source with no checkpoint (neverest opens its own connection for it, src/sync/storage.rs:143-182)
- [ ] Private fields behind a constructor where a value must be guarded
- [ ] Every public item documented and named by the family's rules
- [ ] The MSRV stated; the features checked against the guidelines
- [ ] `cargo semver-checks` in CI, baseline at 1.0.0

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
- [ ] Two readings to pin: a mutable revival whose member carries another body keeps the old one (vector 108 covers the bodiless case alone); a fill settling an item conflict takes the adopted body's summary (vectors 114, 115 to state it)
- [ ] The generator follows G15 (seq order, STORAGE §9.1) and SYNC §5's next-run debt; then the replay's known findings G14 to G17 are lifted in io-pimdir tests/generated
- [ ] Generator readings G18 (a move or copy out of an unsynced collection parks) and G19 (a move of a bodiless based item passes)
- [ ] io-pimdir G20: `retained_by` of a removed item no source binds; G21: the oracle and automatic `sender` references (a MAY)
- [ ] The full-size count profile rerun in release with the collection hierarchy (bytes passes)
- [ ] The flaky crash failure seen once in five runs: not reproduced in 13 runs, likely a half-edited tree; watch for it
- [x] ical-rs release with the bounded zone walk (ical a125d24), io-pimdir on it with `EXTRACTOR` moved, the hostile-zone search case out of tests/pending_vectors.txt (checks/implementation.sh is red until then)
- [x] Consumers after an io-pimdir release (io-pimdir 0.19.0, 2026-11-20; Android Java side left to its session): neverest maps one-way to `KeepLocal`; cardamum and calendula pass no `hash:` key and use `PimdirEnqueued::link_id`; Android follows `PimdirWritten`, `PimdirRekeyReport`, `PimdirLoaded::folded` and may use the canonical collection statements
- [ ] Owner decisions pending: `KeepLocal` over flags and remote deletes; the source a copy or move stages its target's create under; `alt:` keys stated by a producer; the `pimdir` binary's schema `$id` after 1.0; promoting the attachments collection id and `enumerated` to MUST
- [ ] Sections 6 (API review), 7 (campaigns) and 8 (freeze checklist) not started
- [x] The replay harness gains cuts, head answers and rekey so the rekeys, crashes, heads and bodies histories replay through io-pimdir (io-pimdir 5d6419a, 2026-11-21: three summary bugs fixed in rekey, upgrade and hub; bodies 4, 9, 14 are G25, 26 clean, 33 a harness artefact)
- [x] Owner decision G23: does a rekey run the flag axis on the flags its listing states (SYNC §8 "carries each placement's flags, base"; io-pimdir merges them, the generator keeps them): decided 2026-11-21, yes, io-pimdir's reading, stated in SYNC §8 with vector 195 (cairn/log/2026-11-21-a-rekey-runs-the-flag-axis.md)
- [x] The generator follows SYNC on G24 (a rekey's pull takes the member's summary), G25 (an upgrade reports no `Conflicted`), G26 (a bodiless revival leaves `shared_object`, STORAGE §10) and the turned-over G14 (a folded body owed is the collection's divergence); then lift them in io-pimdir tests/generated: done 2026-11-21, the generator follows the spec on all five and io-pimdir's replay runs clean of them (same log entry; io-pimdir cairn/log/2026-11-21-the-replay-findings-lifted.md)
- [ ] The other io-* crates move to cargo-006's client, server and std features at their next breaking release
