---
cairn: change
id: tasks-by-categories
status: landed
created: 2026-10-28
---

# Tasks organised by categories, time on the side

## Why

Pimalaya Android and unfog both organise to-dos the GTD way (pimalaya/android cairn/changes/gtd-by-categories, pimalaya/unfog cairn/changes/gtd-and-time-tracking). The first draft carried the method in an `X-PIMALAYA-GTD` property that no other client reads or writes. It is replaced by a lighter convention: three reserved `CATEGORIES` values, everything else left to the person. Another client then shows and sets the same state, and any tool can capture by adding one category.

Two consumers now share that convention and unfog adds time tracking, which no standard defines. Both belong in one place both consumers read, so they cannot drift: this guide. No table, statement or search field changes: `task_summary.categories` and `category:` (2026-10-27, tasks-carry-their-organisation) already carry everything.

## What

### The convention (GUIDE.md, informative)

- A task is a VTODO. Its state is three reserved `CATEGORIES` values: `inbox` (captured, not yet clarified), `waiting` (someone else owes it) and `someday` (not a commitment). They are the English literals in every locale, compared as `category:` compares (Annex A.2's folding), and a reader shows them under its own labels.
- A capture is a VTODO with `CATEGORIES:inbox`, in any task collection. Clarifying it is an edit of the same item: the summary rephrased, `inbox` replaced by `waiting`, `someday` or nothing, other categories added. Every other category value is the person's own (contexts, projects, anything) and a writer keeps them in order.
- A next action is an open task carrying none of the three, open being any status but `COMPLETED` and `CANCELLED`, a task stating no `STATUS` included (RFC 5545 makes it optional, and many clients omit it). A to-do another client created is therefore a next action.
- The views as queries, so every reader answers them the same:
  - Inbox: `kind:task -status:completed -status:cancelled category:inbox`
  - Waiting: the same with `category:waiting`
  - Someday: the same with `category:someday`
  - Next: `kind:task -status:completed -status:cancelled -category:inbox -category:waiting -category:someday`
- `CONTACT` may name who a waiting task waits on and `ATTACH` a `mid:` URI the mail a capture came from (Annex A.4's `mid`); neither decides a view.

### Time entries (GUIDE.md, informative)

A time entry ties a span to a task by `RELATED-TO` (the task's `UID`, `RELTYPE=PARENT` by default) and has one of two shapes, the consumer offering both:

- **Event**: a VEVENT with `DTSTART`, `DTEND` once stopped, `SUMMARY` the task's, `TRANSP:TRANSPARENT` so it never reads as busy. A running entry has no `DTEND`. Any calendar holds it, Google's and Microsoft's included.
- **Journal**: a VJOURNAL pair, `DTSTART` the instant and `CATEGORIES:start` or `stop`, as unfog 1.x logged it. A VJOURNAL has no end (RFC 5545 §3.6.3), hence the pair. Few servers take VJOURNAL.

Either shape lives in a synced collection or in **the local time collection**: a `text/calendar` collection no source syncs, under no account, never pushed, so moving to a synced collection later is a copy of the same bytes. Its id is the one normative part of this change, since two owners of one store must find the same one: STORAGE §14.3 gains it beside `attachments`, `U+0001` and `time` (§9.2), a SHOULD as the attachments id is. GUIDE.md being informative, it states nothing the parts do not.

### Checks

- vectors/search: tasks in the fixture store carrying each reserved category and none, one with `Inbox` cased so, one with a person's category beside `waiting`; a case per view query above, answered by checks/vectors.py's second reader.
- checks/invariants.sh: the local time collection holds a VEVENT no source binds, `delete_unbound_item` removes it, and no projection offers it.

## Out

- No SEARCH requirement changes and no schema change: the convention is a reading of existing columns, and STORAGE gains only the time collection's id. `parent` and `mid` stay, correct and no longer needed by GTD.
- Durations, reports and which shape to use are the consumer's.

## Open questions

- Settled 2026-10-28: no prefix. The collision with a person's own `inbox` tag is rare and usually means the same thing, and a prefix is uglier in every other client.
