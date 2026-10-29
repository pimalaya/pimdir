---
cairn: delta
change: gtd-hardening
---

## ADDED Requirements

### Requirement: STORAGE §15.3 An add superseding an item
An `add` MAY carry `supersedes: { "collection": id, "seq": n }`, naming the item it replaces. The owner SHALL apply the add and tombstone the superseded item in one transaction, as a `remove` of it would, and record the pair (`supersede_item`). The duplicate check reads the store before the tombstone, so an add parked for a live duplicate link id removes nothing. A superseded item already absent is no failure: the add applies alone. A superseded item no source binds is retained at once, nothing having to push its delete. The producer's gate (§15.6) reads the add's capabilities against its collection and the remove's against the superseded item.

#### Scenario: a parked add keeps its source
- GIVEN an `add` into Next carrying `supersedes` naming task 7 of Inbox, and Next holding a live item under the add's link id
- WHEN the owner drains it
- THEN the row is parked and task 7 stays live in Inbox, untombstoned

### Requirement: STORAGE §4.3 and SYNC §5 The superseded delete waits for the add
`supersessions` SHALL hold one row per superseded item: `(collection, link_id)` the item tombstoned, `(by_collection, by_link_id)` the item the add created, each end cascading with its item. A tombstone `list_superseded_pending` names, one whose superseding item is live and still a pending create of a source syncing its collection, SHALL derive no `Remove` and SHALL NOT be dropped for it. Once every such create is accepted, or the superseding item is withdrawn or gone, the tombstone derives its `Remove` as any other, a plain delete since no pending create of its identity remains to relocate into.

#### Scenario: a refused create keeps the source on its server
- GIVEN task t1 in tasks-a, tombstoned and superseded by t1 in tasks-b, whose create the server rejected and which stays pending
- WHEN tasks-a syncs and the server lists t1
- THEN no push is made and t1 stays bound in tasks-a (vector 71)

#### Scenario: the accepted create releases the delete
- GIVEN the same pair once tasks-b's create was accepted
- WHEN tasks-a syncs
- THEN a plain `Remove` of t1 is pushed, with no destination, and accepted (vector 72)

### Requirement: STORAGE §15.6 Collections refusing tasks
A source MAY declare `x-vtodo` source-wide or on one collection: `none` SHALL mean the collection takes no VTODO resource, `full` that it does. It is read only where a row states it: a source with no `x-vtodo` row refuses nothing by it. The producer's gate SHALL refuse, and the owner's backstop SHALL park, an `add` or `update` whose new resource is a VTODO, and a `move` or `copy` of one, into a collection a source concerned declares `none` for, naming `x-vtodo`, the source and its detail.

#### Scenario: an events-only calendar refuses a capture
- GIVEN source caldav declaring `x-vtodo` `none` on calendar Events
- WHEN a producer gates an `add` of a VTODO into Events
- THEN it refuses with `x-vtodo`, caldav and the detail, and a VEVENT passes

### Requirement: STORAGE §14.1 Replies to a message
`list_replied(ids)` SHALL answer which of the bare message ids `ids` names (a JSON array) a live mail's `in_reply_to` names, mail filed under the `sent` or `drafts` role aside, each id once in code point order: a waiting task's source mail answered (GUIDE §17, umbrella M8).

#### Scenario: one reply, one own reply
- GIVEN a live mail in INBOX replying to asked@x and other@x, one in Sent replying to mine@x, a deleted one replying to gone@x
- WHEN `list_replied` is asked for asked@x, mine@x, gone@x and never@x
- THEN it answers asked@x alone (checks/invariants.sh)

## MODIFIED Requirements

### Requirement: STORAGE §14 rename_collection
`rename_queue_targets` SHALL also follow a pending `add`'s `supersedes.collection` into the new id, beside a `move` or `copy`'s `to`.

### Requirement: STORAGE §14 load
`load` SHALL also answer the tombstones of the collection whose remove is held (`list_superseded_pending`).

### Requirement: STORAGE Annex A.4 wording
The note on `X-` properties SHALL no longer name "the bucket an organising client keeps", which no client keeps any more: an `X-` property is the body's alone, no column carries one.

### Requirement: GUIDE §17 Tasks by categories (informative)
Capture SHALL read as a VTODO with `CATEGORIES:inbox`, `CREATED` and `DTSTAMP` at the capture instant, written as an `add` through the queue (GUIDE §13), or by the owner into a collection no source syncs. A move to another collection SHALL read as one `add` carrying `supersedes`. The writer rules the consumers share SHALL be stated: a task already in the target state untouched; a plain category edit keeping the state and replacing only the person's categories; every line an edit does not change kept byte for byte; `DTSTAMP` restated and `LAST-MODIFIED` restated only where present on an edit that changes a line; `CONTACT` carrying `ALTREP="mailto:..."` given an address; the category filter folded; Next ordered by due, then priority, then oldest captured, other views oldest captured first, "captured at" read from `CREATED`, else `DTSTAMP`.

#### Scenario: writer vectors
- GIVEN vectors/gtd/writers.json
- WHEN a consumer runs each case's operation over its input at its `now`
- THEN it writes the expected bytes, or for a capture a VTODO holding the expected lines (checked by checks/vectors.py for shape)

## REMOVED Requirements
