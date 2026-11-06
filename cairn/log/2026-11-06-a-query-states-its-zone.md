---
cairn: log
change: a-query-states-its-zone
date: 2026-11-06
---

# A query states its zone

SEARCH §8.1 already read a query's years, months, days, `today` and `yesterday` in the zone the client states, but said nothing of which zone, how a span meets a transition, or how a client learns the zone its index placed floating times in. It now says: a span runs from the first instant of its first day in the zone to the first instant of the day after its last, so a day a transition moves lasts 23 or 25 hours and `today` turns over at local midnight; a client SHOULD state the user's zone, the one its indexer states as `floating_zone` (§7), reading it from `index_meta.floating_zone` (`load_index_meta`). UTC stays the default. Edited in place: search-draft-09 is not tagged.

Why: a calendar client (calendula, cairn/changes/pimdir-search/proposal.md there, "Depends on") lists a user's days, and an event at 00:30 in Paris on 1 January is on 31 December in UTC; a floating or all-day event the index placed in Paris lands on the wrong day when the query reads UTC days.

## Rules and their checks

- **The zone of a query's dates** (SEARCH §8.1, §11). vectors/search/: a collection home/Agenda with items 29 to 32 (fixtures event-zoned-midnight.ics, event-floating-late.ics, event-date-new-year.ics, event-zoned-fall-back.ics) and 11 cases stating `zone` Europe/Paris, three of them a `now`: a day, a month and a year each side of 1 January 2027, `today` at 23:30 and at 00:30 local, `yesterday`, a relative amount staying an instant, and 25 October 2026, the 25-hour day. A client reading UTC days over that index fails seven of them. A case's `zone` is asked on an index whose indexer stated it as its floating zone, so the floating event at 23:30 stays on 1 January.
- **The cases the new items join**: `date:today..` and `changed:..1000000000` gain items 29 to 32, and the window 2026-12-11..2027-01-01 the event ending at its end (item 29, 23:30Z to 00:00Z).
- **The format**: queries.json moves to `v` 3 for a case's `zone` and `now` (vectors/README.md's rule: a field a runner must read bumps it), its schema typing both; SEARCH §11, vectors/README.md, GUIDE.md §15 (step 1, the date span, the vector run) and OVERVIEW.md §10 follow.
- **checks/vectors.py**: `point_span` reads a span in a zone; `horizon_left_of` and `cut_of` take a case's `now` and `zone`; `zone` must name an IANA zone and `now` be a UTC instant, a refusal carrying neither; and the hits of every case stating a zone are re-derived over its collection's single events, a zoned time through its `TZID`, a floating time and a date in the case's zone, on §8.1's overlap rule. Proven failing: a case's hits altered and a misspelt zone each fail it.

## Consumers

io-pimdir follows in the same change (`PimdirSearchClock::zone`, `PimdirIndex::floating_zone`, the CLI's `--zone`), re-vendoring these vectors; checks/io-pimdir.rev moves once both are committed.
