---
cairn: log
change: calendar-until-and-location
landed: 2026-08-16
---

# Absorb until and location into the calendar summary

The calendar convention was written from what a CalDAV connector had in hand. pimalaya-linux had been writing two fields beside it for months, and both turned out to be better than a private dialect.

## `until`, because it is the missing half of the recurrence answer

[pimdir issue 1](https://github.com/pimalaya/pimdir/issues/1) established that `sort_key` holds a series' **first** occurrence and that a date-range read therefore needs the recurrence expanded above the store. True, and expensive: without a bound, a reader must expand every recurring item it holds before it can rule any of them out.

`until` carries the `RRULE`'s `UNTIL` verbatim, so `dtstart` and `until` bracket the series and a reader drops what cannot intersect its range without generating one occurrence. It is a few bytes, present only on bounded recurring items.

What it deliberately does not claim: absent means the bound is **unknown**, not that there is none. A rule bounded by `COUNT` states no `UNTIL`, so a reader finding none expands to decide, which is the same thing it would have done for every item before.

## `location`, because a row shows it

The other kinds already carry their display fields: mail has `from` and `to`, a card has `emails`. An agenda row is a time, a title and a place, and the place was the one a reader had to open the body for. Optional, verbatim, no normalisation.

## Not taken

Nothing else from the linux dialect. `tzid` and `all_day` are the same facts the convention already states as `dtstart_tzid` and `dtstart_value`, so they are spellings rather than fields, and the convention keeps its own.

Both additions are optional at `v: 1`, so older rows read as unknown and older readers ignore them, exactly as [in_reply_to](./2026-08-16-mail-in-reply-to.md) did for mail on the same day.
