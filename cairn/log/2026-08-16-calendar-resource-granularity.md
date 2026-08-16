---
cairn: log
change: calendar-resource-granularity
landed: 2026-08-16
---

# The calendar item is the resource, not the component

[Issue 1](https://github.com/pimalaya/pimdir/issues/1) read `PRIMARY KEY (collection, link_id)` against the way iCalendar identifies a recurring series: RFC 5545 §3.8.4.4 gives an override the same `UID` as its master, so a series plus three modified instances looked like four rows contending for one key. It proposed a composite link id of `UID` plus `RECURRENCE-ID`, and asked for it before the freeze closes the free window.

The key was not the problem, and the proposed remedy would have been one. RFC 4791 §4.1 requires the components sharing a `UID` to live in one calendar object resource, and that `UID` to be unique within the collection holding it, so at resource granularity `(collection, link_id)` is exactly the uniqueness CalDAV itself enforces. A composite key would have put four rows behind one href and one ETag, so `bindings.base_revision` and the §10 merge would have had to agree with themselves across four rows describing one HTTP entity; a push would still have had to reassemble the resource, since an override cannot be `PUT` alone; and a delete and a §16 revive would have fanned out over four keys.

What was actually missing is that nothing **stated** the granularity, which is what made the other reading available. §13 said "a calendar object resource holds a tree of components" in passing and then fixed a summary and a key as though the item were one component.

## What landed

No schema change. migrations/0001_init.sql is untouched, which is also why the freeze deadline the issue invoked did not apply.

**§13 now opens with the granularity rule.** The item is the calendar object resource: the master, every `RECURRENCE-ID` override and the `VTIMEZONE`s they reference, one blob under `link_id = UID`. An override is a body edit of the resource rather than an item of its own. A connector to an instance-granular source MUST reassemble the set before writing it, or two stores of the same calendar disagree about how many items it holds.

**The summary carries times verbatim.** `component` replaces `kind`; `dtstart` is carried as written beside `dtstart_tzid` and `dtstart_value`; `dtend` and `due` the same; `recurring` tells a reader it must expand. A reader with a time zone database re-derives an instant in its own zone, and one without displays the wall time the calendar wrote rather than a UTC claim a writer fabricated. No resolved instant is duplicated in `meta`, because `sort_key` is already returned by the paging reads and is the single resolved projection.

**The sort key is stated per component and per shape.** `DTSTART` for a `VEVENT` or a `VJOURNAL`, `DUE` then `DTSTART` for a `VTODO`, which need not carry a start at all. UTC verbatim; zoned resolved through the document's own `VTIMEZONE`, earlier offset on a fold and post-transition offset on a gap; an unresolvable zone read as floating; date-only at midnight; floating on the wall clock. The last three are named as conventions rather than facts.

**§13 stopped overclaiming.** It justified the key as "what lets a date-range read page a calendar with the same statements", which is false for exactly the items a user sees most: `DTSTART` on a series is its first occurrence, fixed for life. It now says the key is the first occurrence and that a date-range read over recurring items needs the recurrence expanded above the store.

**§11 names `sort_key` the one column exempt from byte-identical encoding**, since a zoned key resolves through a tzdb version. §9.3 already answered why that is harmless; the two sections now point the same way.

## Where the issue was not followed

**The composite link id**, for the reasons above.

**`''` for an unresolvable zone.** The issue proposed it; on its own reporter's corpus that is 118 of 128 items sent to the far end of every listing. Reading the wall time as UTC is wrong by an offset and keeps the item near its place, so `''` is kept for a value that does not parse at all.

**`recurrence_id` in the summary.** Under resource granularity the item is the whole set, so what a reader needs is `recurring`, not the id of one instance.

## What this asked of the connectors

calendula was the connector holding the rule wrong in both directions, and moved with the spec on the same day: it summarised the first `VEVENT` of a resource rather than the master, its `meta.start` asserted UTC while carrying local wall time for every zoned event, and its gcal backend filed a Google exception as an item of its own with no `RECURRENCE-ID` at all. Its own log entry records the detail.

pimalaya-linux and pimalaya/android write this same summary under the older names (`kind`, `start`, `tzid`, `all_day`) and are now out of step.

## Left open

The linux writer carries two fields §13 does not: `location`, and `until`, the bound of a recurrence rule. `until` is a better answer to the date-range problem than anything in the issue, since it bounds a range query over a recurring item without materialising its occurrences, and it belongs in §13 if the convention takes it. That is a change of its own, not a footnote to this one.
