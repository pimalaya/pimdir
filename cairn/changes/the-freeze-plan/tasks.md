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
- [ ] The model: accounts, sources, collections, the four kinds, the structure cases of pim-corpus/proposal.md enumerated
- [ ] The scenario catalogue, read from himalaya, cardamum, calendula, neverest and the Android app: every queued action each issues, every sync sequence neverest runs
- [ ] The writer: a store from the canonical statements of queries/ alone, checked by checks/schema.sh's rules
- [ ] The scripted remote states, for scripted connectors
- [ ] The oracle: reads, counts, overlay, search answers after each event
- [ ] Shrinking: a failing seed reduced and written as a vector
- [ ] Profiles: structure, count (100k items), bytes (large bodies), quirks
- [ ] Its own checks in `nix flake check`

## 3. io-pimdir's differential tests

- [ ] Readers against the oracle on generated stores, queued rows of every producer included
- [ ] The engine replaying generated scripts through scripted connectors: no loss, convergence, queue order
- [ ] A crash injected at every step of a replay, the store reopened and the run finished
- [ ] The search index refreshed after each event equal to a rebuild
- [ ] The count and bytes profiles under the scale tests

## 4. The seams in the standard

- [x] Vectors of a refresh driven by the change feed (STORAGE §4.5): stamps after each kind of write, a summary row changed under an unchanged item, a rename, a purge, an erasure
- [x] Every SHOULD and MAY of STORAGE, SYNC and SEARCH listed with the consumers relying on it; each promoted, documented or kept with a reason
- [x] The overlay of STORAGE:961 decided among them

## 5. Owner decisions

- [x] D2 decided (2026-11-20): in sync-v1
- [ ] D2 landed: SYNC text, a vector, io-pimdir, neverest mapping its one-way authority to it
- [x] D3 decided (2026-11-20): search inside io-pimdir 1.0, SEARCH released with the other parts
- [x] D4 decided (2026-11-20): outside
- [ ] D4 stated in the `pimdir` binary's help and README
- [x] D5 decided (2026-11-20): two campaigns in a row with no spec break

## 5b. Search in v1

- [ ] README.md, every Status line and AGENTS.md: the three parts release together
- [ ] The query language reviewed once: grammar, every form and every refusal listed, each refusal coded
- [ ] Query vectors: every form of the grammar, run over generator stores, not one fixed store
- [ ] Extraction vectors per kind: MIME parts, charsets, attachments; vCard fields; iCalendar fields, time zones, all-day items, recurrence expansion up to its bound; Unicode normalisation and case
- [ ] Threads, snippets and coverage (`complete`, `filling`, `missing`) pinned by vectors
- [ ] A page token stays valid, or is refused coded, across a refresh between two pages
- [ ] The generator's oracle answers every search the vectors ask
- [ ] The freeze checklist gains `search-v1.0.0`; checks/frozen.sha256 the search statements and signatures

## 6. io-pimdir's public API

- [ ] The list of public items, each kept, made private or removed
- [ ] `non_exhaustive` on every enum and struct expected to grow
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
