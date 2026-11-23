---
cairn: change
id: the-consumers-follow-draft-17
status: active
created: 2026-11-23
---

# The consumers follow storage-draft-17

storage-draft-17, sync-draft-15 and search-draft-17 (this repository at e40b258) and io-pimdir 7f16b27 implementing them reach no consumer yet: every app is on io-pimdir 0.19.1 or an older git pin. Seven plans move them, each run by its own session, all launchable at once. frame.md is what they share (target, who edits what, git, CPU sets and locks, accounts, how a lane decides); each plan cites it.

## The lanes

| Lane | Plan | Measured on 2026-11-23 at 7f16b27 |
| --- | --- | --- |
| io-pimdir (and this repository's vectors) | io-pimdir cairn/changes/what-the-consumers-need | the 19 rekey and 4 drain tests of a-smaller-sync still pass, so the defects stand; CI red (a per-feature dead code, the Windows build since 85503f4); three drops: CI green, the engine following SYNC with a vector per case, the release candidate |
| neverest | neverest cairn/changes/follows-storage-draft-17 | no compile break, one test; G1 a reproduced silent loss (`sync --reset` drops local properties); settled collections skipped |
| himalaya | himalaya cairn/changes/follows-storage-draft-17 | 7 compile breaks, 4 tests, then 867 pass; `pimdir status` 30 s at 517k |
| cardamum | cardamum cairn/changes/follows-storage-draft-17 | 15 compile breaks, then 366 pass; whole-book walks 24 to 34% slower, other reads 2 to 7 times faster |
| calendula | calendula cairn/changes/follows-storage-draft-17 | 9 compile breaks, 2 tests; one bad queue row fails every event listing; a month window 2.6 s at 10k events |
| carillon | carillon cairn/changes/follows-storage-draft-17 | no break; a store replaced under a running watch is never read again, one alarm fired twice |
| Android | android cairn/changes/follows-storage-draft-17 | the Java store ported (66 app statements, 29 forks, 5 index statements): 509 JVM tests and every sync vector fail until then; three to five days |

## How they meet

- Every app lane starts on the git pin of 7f16b27 and pins only pushed revisions after it (frame §4).
- The io-pimdir lane ships three drops; the owner re-signs and pushes each, the app lanes re-pin and re-run their gate. Drop 1 carries what the Android release library needs to link (`sql::search` under `indexer`).
- The five CLIs share one store: none is released before all five pass their gates on one io-pimdir revision, the cross-app check included (a store neverest writes read by the four others, their queued rows drained by neverest).
- What a lane needs from io-pimdir goes to its needs-io-pimdir.md, answered in the io-pimdir lane's answers.md. Asked by three lanes: queue rows decoded one by one, so one bad row no longer hides the others (cardamum, calendula, himalaya); per-collection counts for `pimdir status` (cardamum, himalaya).
- Every app's `cargo deny` is red at its head on url 2.5.8 (RUSTSEC-2026-0592): each lane bumps url to 2.5.9 in its own Cargo.lock.

## The owner's decisions

Each plan's proposal lists its decisions with the default it takes; the ones that cross lanes:

- io-pimdir D1 to D13, D10 (R6a, a rule change in SYNC §8) and D6 (a `trace!` line per fixed branch as the oracle's witness) first; the yes to 0.20.0 when launching that lane (its task 5.3).
- Labels and properties: read through the query fields, no CLI verb writing them yet (cardamum D3, calendula D3, himalaya D1).
- `--sort` takes SEARCH's names, old values kept as hidden aliases (calendula D1, cardamum D2; himalaya already does).
- A system flag's case (himalaya D3, io-pimdir D13): stays unruled in 0.20.0.
- Android: the Java store is ported (shape A); serving it from io-pimdir in Rust (shape B) stays a later proposal.

## After the lanes

The tag v0.20.0 (the workflow publishes), checks/io-pimdir.rev and the tags storage-draft-17, sync-draft-15 and search-draft-17 here, each app's pin swapped for 0.20, then the app releases in the owner's order: tasks.md.

## Out

unfog, journal, the Linux app and the other io-pimdir consumers: not asked for; each refuses the CLIs' store until moved.
