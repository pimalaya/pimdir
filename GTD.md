# Pimalaya task conventions

Status: gtd-draft-01, informative, requiring storage-draft-05 and search-draft-05

How Pimalaya's task consumers (the Android app, unfog) organise to-dos the GTD way over a pimdir store, and how they keep time spent on them, so that a task one of them writes reads as the other would have written it. Everything here is a reading of standard iCalendar properties and of what the store already holds ([STORAGE.md](./STORAGE.md), [SEARCH.md](./SEARCH.md)); it adds no table, column, statement or rule to the store, and another client that never read it sees and edits the same tasks.

This document is informative and versioned apart from the three parts, so the store freezes without it: a task consumer states the version it follows, and a change here bumps `gtd-draft-NN` alone. Where it and a part disagree, the part wins. §n of a part is written STORAGE §n, SYNC §n, SEARCH §n; GUIDE §n is the [implementation guide](./GUIDE.md).

## Contents

1. [Tasks by categories](#1-tasks-by-categories)
2. [Time entries](#2-time-entries)
3. [Test vectors](#3-test-vectors)

## 1. Tasks by categories

How Pimalaya's task consumers (the Android app, unfog) organise to-dos the GTD way, from the columns the store already carries. It is a reading of `task_summary.categories` and `status`, not a rule of the store: another client sees and sets the same state, and a task created anywhere takes part.

- **State**: three `CATEGORIES` values are reserved, `inbox` (captured, not yet clarified), `waiting` (someone else owes it) and `someday` (not a commitment). They are written as those English literals in every locale, compared as `category:` compares (folded as STORAGE Annex A.2 folds `fn`, so `Inbox` is `inbox`), and shown under the reader's own labels. Every other value is the person's own: a context, a project, anything.
- **Capture**: a VTODO with `CATEGORIES:inbox`, `CREATED` and `DTSTAMP` both the instant of capture in UTC (`20261028T090000Z`), in any collection that takes tasks (one no source declares `x-vtodo` `none` for, STORAGE §15.6). It is an `add` through the queue (GUIDE §13), from whose body the owner derives `upsert_task_summary`'s row; into a collection no source syncs, the owner writes it itself, as §2 writes an entry.
- **Clarify**: an edit of the same item, an `update`. The summary may be rephrased, `inbox` is replaced by `waiting`, `someday` or nothing, other categories are added; a writer edits only the three values and keeps every other category in order. Filing it into another collection, renamed or not, is one `add` there carrying `supersedes` that names the source item (STORAGE §15.3), rather than a `move`: the owner applies the add and the source's tombstone in one transaction and pushes the source's delete only once the add is pushed, so a refused create keeps the capture on its server. A filed task keeping its `UID` is delivered, by a connector able to, as a server-side move of the source member then a write of its body (`list_superseded_bindings`, SYNC §4): a server keeping one `UID` per account, as Fastmail does, refuses the plain create while the source holds it.
- **Next action**: an open task carrying none of the three. Open is any status but `COMPLETED` and `CANCELLED`, a task stating no `STATUS` included, so a to-do another client created is a next action.
- **Links that decide nothing**: `CONTACT` may name who a waiting task waits on, written `CONTACT;ALTREP="mailto:<address>":<name>` when the address is known, the address as the text when no name is, and `CONTACT:<name>` otherwise; an `ATTACH` `mid:` URI names the mail a capture came from (`task_summary.mid`, a `source` reference, STORAGE §14.2).
- **Captured at**: `CREATED`, else `DTSTAMP`, so a task another client wrote without `CREATED` still has an age.

The views are queries (SEARCH §8), global across accounts and collections, so every reader answers them alike; a category filter is one more `category:` term, folded as the state is, so `Work` finds `work`:

| View | Query |
| --- | --- |
| Inbox | `kind:task -status:completed -status:cancelled category:inbox` |
| Waiting | `kind:task -status:completed -status:cancelled category:waiting` |
| Someday | `kind:task -status:completed -status:cancelled category:someday` |
| Next | `kind:task -status:completed -status:cancelled -category:inbox -category:waiting -category:someday` |

vectors/search/queries.json holds a case per view over items 17 to 21 of the fixture store, and checks/vectors.py re-derives their hits from the fixtures' bytes.

A review asking which waiting tasks were answered passes their `task_summary.mid` values, bare, to `list_replied`: an id it answers is a mail the task came from that someone has replied to, a reply the person filed under `sent` or `drafts` not counting.

Next lists the soonest `DUE` first, as an instant on STORAGE Annex A.3's rules, a task stating none after every one that does, then by `PRIORITY`, 1 first and 9 last, 0 or none after 9, then the oldest captured first. Inbox, Waiting and Someday list the oldest captured first.

**Writing.** Both consumers edit a task alike, so an edit made by either reads as the other would have written it:

| Edit | What it writes |
| --- | --- |
| Setting the state (`inbox`, `waiting`, `someday` or none) | Nothing when the task already carries exactly that state among the three, its spelling and casing kept. Otherwise only the `CATEGORIES` lines holding a reserved value change: the first reserved value becomes the new state's literal, the other reserved values go, the person's values stay in order, and a line left empty goes. With no reserved value to take the place of, the state is a line of its own after the last `CATEGORIES` line, else after the task's last property. |
| Setting the person's categories | The reserved values stay where they stand. Nothing when the person's values, in document order, already are the new ones. Otherwise the new list, its values trimmed, the empty ones and the repeats (folded) dropped, takes the place of the first person's value on any `CATEGORIES` line, the person's other values go, and a line left empty goes; with no person's value to take the place of, the list is a line of its own, placed as a new state is. A reserved value among the new ones is refused: the state is set by the edit above. |
| Setting the contact | Every `CONTACT` replaced by the one written as above, where the first stood, else after the task's last property; nothing when the task carries exactly that one. |
| Capturing | A new VTODO as Capture says, its `UID` and `SUMMARY` the writer's, nothing else required. |
| Any edit that changes a line | `DTSTAMP` restated to the instant of the edit, in UTC, where it stands, after the task's last property when absent; `LAST-MODIFIED` restated to the same instant only where the task carries one; `SEQUENCE` and `CREATED` untouched. |
| Any edit | A line it does not change keeps its bytes, folding included. A line it writes is encoded afresh: text escaped as RFC 5545 §3.3.11 says, its parameters kept, folded at 75 octets. A task carrying the edit's result already is written back unchanged, and nothing is queued. |

vectors/gtd/writers.json holds these edits as cases (§3).

## 2. Time entries

No standard ties time spent to a task. A consumer tracking it writes entries tied to the task by `RELATED-TO` (the task's `UID`, `RELTYPE=PARENT` by default) in one of two shapes:

- **Event**: a VEVENT with `DTSTART`, `DTEND` once stopped, the task's `SUMMARY` and `TRANSP:TRANSPARENT`, so it never reads as busy. A running entry has no `DTEND`. Any calendar holds it. Its summary is `upsert_event_summary`'s, `dtend` `NULL` while it runs.
- **Journal**: a pair of VJOURNALs, `DTSTART` the instant and `CATEGORIES:start` or `stop`, as unfog 1.x logged it. A VJOURNAL has no end (RFC 5545 §3.6.3), hence the pair. Few servers take VJOURNAL. Its summary is `upsert_journal_summary`'s.

Either shape lives in a synced calendar collection, or in **the local time collection** when the person keeps time on the device: a `text/calendar` collection under no account that no source syncs (STORAGE §14.3), holding events and journals as any calendar does, whose id is `U+0001` and `time` (`\u0001time`), a name no server gives a calendar, so two owners of one store find the same one. Declare it once, `set_collection_kind` with that id, no account and kind `text/calendar`, then `set_collection_name(collection, 'time')`; write each entry with `insert_item` and its summary, nothing binding it; remove one with `delete_unbound_item` then `release_pins`. No source syncs it, so nothing is pushed; moving entries to a synced collection later is a copy of the same bodies there and a delete here. checks/invariants.sh runs the collection, a running event, a journal entry and their deletion.

## 3. Test vectors

- **vectors/gtd/writers.json** with vectors/gtd/fixtures/: the edits of §1's writing table, each case an `input` task, an `edit` (`set-state`, `set-categories`, `set-contact`, `capture`, `captured-at`), the file's `now`, and what it expects: the output's `bytes`, `unchanged`, `refused`, for a capture the `vtodo` lines and `names` it states, for a reading its `value`. A task consumer reads the input as bytes, runs the edit at the case's `now`, and compares the output with the expected fixture byte for byte, a capture comparing the lines its VTODO holds, unfolded, and the properties it names. The file states `v` 1 and conforms to vectors/schema/gtd-writers.schema.json.
- **vectors/search/queries.json** holds a case per view of §1 over the tasks of the search fixture store (SEARCH §11), items 17 to 21 written for them, which every index answers.

checks/vectors.py reads §1's view table from this document and re-derives each view's hits from the fixtures' bytes, and checks each writer case's shape and what its edit may change from the bytes on both sides.
