---
cairn: change
id: the-freeze-plan
status: draft
created: 2026-11-20
---

# The freeze plan

## Why

Readiness for v1 has been judged by audits that always find something, so the freeze keeps moving. This plan replaces "no new finding" with gates that measure what a freeze would cost: at its end, storage-v1.0.0, sync-v1.0.0 and search-v1.0.0 can be tagged at one commit and io-pimdir 1.0.0 released, or the plan names the finding that stops them. It builds on the-lines-before-v1 (the index of the older open lines, 2 of them blocking) and on the freeze gate rehearsed on 2026-11-13 (cairn/log/2026-11-13-the-freeze-gate-is-rehearsed.md).

## What a freeze costs

After v1, a schema change is a migration (STORAGE §6, rehearsed), a rule, a statement or a vector is a minor, and sync state of an older major is converted by the engine (SYNC §10). What a later fix cannot undo cheaply: the six `store_meta` columns a program judges a store by, 0001_init.sql as the base every migration starts from, the v1 payload schemas, the frozen statement signatures, the query language people type, the answers the search vectors pin, and the io-pimdir 1.0 public API. The index itself is rebuilt, never migrated (SEARCH §2), so its schema is the cheapest of these to change. A finding is therefore sorted by door:

- **spec break**: needs a change to one of the frozen items above, or a sync rule that is not additive. Blocks the freeze.
- **spec minor**: a rule, a statement or a vector added, breaking no store. May follow the freeze.
- **implementation**: io-pimdir or a consumer departs from the spec. A patch, never a blocker, unless it is io-pimdir's public API.

## What

1. **Y2**, neverest's `Remove` contract against a real IMAP server without UIDPLUS: maddy from nixpkgs, started by neverest's own integration test, run in its CI.
2. **A generator owned by pimdir**, depending on no app and not on io-pimdir: `(generator version, seed, profile)` to a history (accounts, sources, collections, items of the four kinds with pim-corpus's structure cases, remote events, queued actions, sync rounds, purges, erasures, crashes), a store written by the canonical statements of queries/ alone, the scripted remote states, and an oracle stating what every read, count, overlay and search answers after each event. The scenarios are taken once from how himalaya, cardamum, calendula, neverest and the Android app use the store, by reading them, never by running them. pim-corpus folds into it.
3. **Differential tests in io-pimdir** driven by the generator: its readers against the oracle; its engine replaying the scripts through scripted connectors, holding no loss (every body ever written reachable or retained), convergence (a second run changes nothing), recovery from a crash at any step and queue order; its search index refreshed after each event equal to one rebuilt from scratch; the `count` and `bytes` profiles for scale.
4. **The seams in the standard**: vectors for a refresh driven by the change feed (STORAGE §4.5), so no implementation can pass while missing a stamp; and a review of every SHOULD and MAY of STORAGE, SYNC and SEARCH a consumer's correctness depends on (the overlay of STORAGE:961 is one, the retained items `load_items` leaves out another), each promoted, documented or left with a reason.
5. **The owner's decisions** (below), landed before the campaigns.
6. **io-pimdir's public API reviewed for 1.0**: 334 public types, 78 public enums of which 6 are `non_exhaustive` (2026-11-20). Each enum or struct expected to grow is marked, fields are made private where a constructor must guard them, every public item is documented and named by the family's rules, the unused ones removed, the MSRV stated, and `cargo semver-checks` runs in CI from the 1.0 baseline.
7. **Campaigns**: a fixed set of seeds over every profile, run against io-pimdir; every finding sorted by door. The stop rule: two campaigns in a row with no spec break, each campaign's failures shrunk into vectors.
8. **Release mechanics**: pimalaya/nix's release workflow refuses a tag whose version is not the crate's (and marks a tag holding `-` a pre-release); the freeze commit's checklist brought to the current draft names (search-draft-14, not search-draft-10); io-pimdir passes the frozen tree with no pending vector.

## Search in v1

SEARCH is released with STORAGE and SYNC (the owner, 2026-11-20), reversing README.md: "SEARCH is released later". Its vectors today hold about 221 queries over one 12 KB store and a few chunk cases; what v1 freezes needs more:

- **The query language** is a contract of every CLI that exposes it (himalaya, cardamum, calendula) and of the Android app: its grammar reviewed once (fields, negation, OR, dates and ranges, kinds, sort, page tokens), every form pinned by a vector, every refusal coded.
- **Extraction per kind**: MIME parts, charsets and attachments; vCard fields; iCalendar fields, time zones, all-day items and recurrence expansion up to its bound; Unicode normalisation and case; each by vectors over generated bodies, with the oracle.
- **Answers over generated stores**: the search vectors run over generator stores, not one fixed store; threads, snippets, coverage (`complete`, `filling`, `missing`) and the stability of a page token across refreshes included.
- **The change feed seam** (above) and refresh equal to rebuild after every event.
- **Release mechanics**: README.md and every Status line say the three parts release together; the freeze checklist gains `search-v1.0.0`, and checks/frozen.sha256 the search statements and their signatures.

## Owner decisions

- **D1, where the generator lives** (agreed 2026-11-20): a Rust crate in this repository, depending on no Pimalaya crate, so io-pimdir takes it as a dev-dependency and the standard owns its own test data.
- **D2, one-way authority** (agreed 2026-11-20): a remote-only change on a source the store is authoritative over is adopted today (io-pimdir `PimdirHub::reconcile`, SYNC.md:347-349 asking `PreferLocal` only when both sides changed). In sync-v1: a policy value making such a change a divergence, additive to the conflict policies, with a vector; neverest v1 depends on it.
- **D3, search in io-pimdir 1.0** (decided 2026-11-20): inside io-pimdir 1.0 and its semver, SEARCH being released with the other parts.
- **D4, the `pimdir` operator binary** (io-pimdir's `cli` feature, agreed 2026-11-20): outside the 1.0 contract, stated so in its help and README.
- **D5, the stop rule** (agreed 2026-11-20): two campaigns in a row with no spec break.

## Out of scope

The read-back and the owner fence (decided after v1 on 2026-11-19), the consumers' releases.
