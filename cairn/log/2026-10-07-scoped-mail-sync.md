---
cairn: log
change: scoped-mail-sync
date: 2026-10-07
---

# A mail sync lists newest first, within a scope on the `Date`

The joint plan of MOA and Pimalaya Android (`cairn/changes/scoped-mail-sync/`), now landed: a mail collection syncs under a scope on the `Date` header, in rounds answered page by page newest first, every listed member named with its meta, coverage recorded per collection and source. The change folder stays where it is, `status: landed`, as this repository keeps its landed changes.

## What landed here

- **a2e92af.** SYNC §4 (the paged seam: page, resume cursor, last page; every member carries its meta), §5 (the scope, its two-day margin, absence meaning deleted only in scope, explicit removals and local changes whatever the date, rounds stamped and closed, the checkpoint bound to its scope), §3, §6 and §12 (probes and `Probed` gone; creates wait for the page that lands them; naming on §6's identity rules). STORAGE: coverage and the open round per `(collection, source)`, `bindings.round`, `collect_before` (§11.3), the mail readers (§14.1), the `probes` table and its statements removed; Annex A.1: the attachment mark without the body, replaced by the walk of the parts. Guarded by invariants.sh (rounds, coverage, collection, readers), sync vectors 06, 07, 21, 25, 31 rewritten and 34 to 45 added, `meta_attachment` in summaries.json, and vectors.py refusing any `Remove` a case did not stage.
- **00535c1.** A band round infers no delete of an undated member (SYNC §5, STORAGE §10, `sources.round_band`); its own entry, 2026-10-07-a-band-round-keeps-undated-mail.

## What landed elsewhere

- io-pimdir 35a1c3f (the engine and store), f9b13f8 (an empty mail `date` stored as `NULL`), ff28408 (the band round of 00535c1).
- io-msgraph 41922fb, 00ef069: the page size preference.
- neverest 010940c..b3d65bb: the safety fixes of §8 folded, the scoped connectors (2b59f13), bodies following their page (6f9017c), one unfiltered Graph delta link per folder with a scope listed by band on `sentDateTime` (3938d10), the undated workaround removed (9ebf608).
- himalaya 32d2876 (coverage in `pimdir mailbox list`, the attachment mark as stored), 065e7e4 (keyset envelope pages), e71e9cb; calendula and cardamum pinned to the same io-pimdir.
- Android c2782a8, 57e44ed, 7bb0e68 (a short first sync by chunks of 50), 0bebef8 (Graph as neverest), eacb71e.
- MOA ca77922..8a90209: no scope by default, coverage shown in Réglages and to the agent.

## What the implementation corrected

Graph caps message delta pages at 512 even when asked 1,000; the proposal's measurement read it as honoured. Graph mail ended bound to no scope, its filtered delta replaced by an unfiltered link and band listings (decided 2026-10-07). Both recorded in the proposal's "What changed during implementation".

## Left open

Task 0's measurements (an IMAP 100k benchmark, Gmail's paced read rate, store insert rates natively and over JNI, Graph's skip token lifetime); the new Graph and Gmail listings validated live (the tests compile, none ran on a tenant or a Gmail box); Gmail's daily quota accounted across runs. Each is an unticked line of the change's tasks.md.

Folded into 0001; draft-04 is not tagged yet, so the number stays.
