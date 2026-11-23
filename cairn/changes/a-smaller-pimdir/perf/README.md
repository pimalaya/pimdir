# The performance pass

Binaries: old = io-pimdir 00727ba (round 4, storage-draft-16), new = io-pimdir 3a1f3eb (storage-draft-17, this change). Built from git archives under .pimdir-night/perf (build.sh). Measures on core 12, hyperfine medians in ms, notmuch 0.40.

## Import (GNU time, writeback body flush, core 12)

| | sync wall | sync user + sys | index wall | index user + sys | total wall |
| --- | --- | --- | --- | --- | --- |
| 517k old | 368.3 s | 128.4 s | 215.0 s | 100.2 s | 583.3 s |
| 517k new | 338.7 s | 119.7 s | 190.4 s | 97.6 s | 529.1 s |
| 1M new | 827.1 s | 307.7 s | 448.7 s | 215.0 s | 1,275.8 s |
| 1M notmuch (2026-11-21) | | | | | 1,303 s (1,027 s CPU) |

## Queries at 1M, first pass (2026-11-23 02:35, a disk copy ran meanwhile: indicative)

count / page of 50 / threaded page of 50; notmuch, old, new.

| query | count | page | threads |
| --- | --- | --- | --- |
| all mail | 54.51 5.68 5.40 | 258.84 11.34 10.96 | 275.35 12.83 12.57 |
| unread | 21.16 6.94 6.83 | 79.13 9.81 9.48 | 85.37 11.60 11.11 |
| flagged | 5.75 4.85 4.75 | 16.22 6.86 6.70 | 18.69 8.71 8.44 |
| from address | 12.62 5.32 5.69 | 17.42 7.07 7.33 | 18.40 7.70 8.10 |
| from name | 4.05 3.64 3.54 | 8.29 6.42 6.17 | 9.74 7.53 7.23 |
| subject word | 5.22 3.96 3.85 | 14.43 7.33 7.21 | 16.43 8.84 8.94 |
| common word | 87.82 51.52 51.71 | 283.62 60.33 60.15 | 299.71 62.06 62.09 |
| mid word | 8.74 6.17 6.09 | 26.95 9.68 9.72 | 29.97 11.08 11.16 |
| rare word | 2.33 2.49 2.40 | 4.17 4.72 4.47 | 6.00 6.40 6.24 |
| phrase | 16.41 8.48 8.36 | 27.98 13.29 13.43 | 29.27 14.13 14.01 |
| two words | 7.55 6.55 6.44 | 17.61 10.44 10.18 | 18.53 11.22 11.12 |
| negation | 9.21 7.46 7.42 | 23.52 11.02 11.00 | 25.22 12.00 11.92 |
| prefix | 5.77 5.04 4.95 | 12.26 8.33 8.11 | 14.62 10.40 10.08 |
| date month | 24.49 6.48 6.73 | 40.09 8.82 8.74 | 42.21 10.60 10.09 |
| combined | 4.96 5.99 5.72 | 6.34 8.46 8.84 | 8.39 10.18 9.96 |
| unread word | 7.12 6.70 6.63 | 14.61 10.67 10.67 | 15.95 12.07 11.87 |
| folder | 2.60 2.57 2.33 | 3.28 3.46 3.24 | 4.46 5.11 4.89 |

The new binary holds the old one's level (every difference within noise). Behind notmuch: rare word page and threads, combined on all three, folder threads; rare word count and folder page are ties. Every count is identical between the old and the new 1M stores.

## Leads (one independent agent each, 02:45 to 06:30)

| lead | core | measures owned |
| --- | --- | --- |
| floor | 2 | the fixed cost of every query (open, checks, ATTACH, coverage, output): rare word, folder counts |
| rare | 6 | per-hit presentation of small pages: rare word page and threads, folder threads |
| combined | 8 | combined on all three, date and HOLDS_CALENDARS |
| import | 10 | the index build and the sync's sys time against notmuch new |
| incr | 14 | the no-op, the incremental and the whole rewrite of index.hits |

Each agent works on its own copy of io-pimdir db31aab and of the 517k store; the lead re-measures every patch head to head on core 12, keeps it only when it is better beyond noise with identical answers, runs the gate and commits.
