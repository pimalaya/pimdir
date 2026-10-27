---
cairn: log
change: search-override-only-series
date: 2026-10-27
---

# A resource holding only an override answers its date

SEARCH §7 gave no occurrence to a resource holding overrides and no master. That is what an attendee invited to a single instance of a series stores, so the one meeting they were invited to never answered `date:`.

- **SEARCH §7**: a resource holding overrides and no master yields each override as an occurrence, from its own `DTSTART` to its end by the span rules; an `RRULE` with no `DTSTART` still yields none. A task with a `DUE`, no `DTSTART` and no `RRULE` is one zero-length occurrence at its due time, as `kind:task date:..2026-10` already pinned. A floating time and a date are read in the time zone the indexer states, UTC when it states none, as §8.1 reads a query's dates.
- **vectors/search**: fixture event-override-only.ics (one `RECURRENCE-ID` override, no master), item 15 of store.json in home/Calendar. New case `date:2026-09-03` → home 15, a Thursday no other item meets. `date:today..` and `changed:..1000000000` gain home 15.

Guarded by the `date:2026-09-03` case, which an implementation following the old rule answers empty; checks/vectors.py checks the fixture and the hit resolve. checks/schema.sh, names.sh, invariants.sh and vectors.py pass. draft-04 is not tagged yet, so the number stays.
