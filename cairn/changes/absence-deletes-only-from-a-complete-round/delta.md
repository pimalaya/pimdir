---
cairn: delta
change: absence-deletes-only-from-a-complete-round
---

## MODIFIED Requirements

### Requirement: SYNC §5 Which absences delete
An absence SHALL be read as a delete only when a closed, complete round of the source did not list a member in its scope; such an absence drops the member `Deleted`, the item is marked deleted, and every other source binding it projects a `Tombstone` and pushes its `Remove` (§9). A page before the last, an interrupted or restarted round, a head, a delta, a member out of scope, an undated member of a band round and a parked round are no absence. A `Remove` MUST be derived from a tombstone the store holds and from nothing else.

#### Scenario: a partial round deletes nothing anywhere
- GIVEN an item bound by sources imap and jmap, and a round on imap interrupted after a page that did not list it
- WHEN the run ends
- THEN imap's binding stays, the item stays live, and jmap has no `Remove` to push (vector 74)

#### Scenario: a closed round's absence propagates
- GIVEN the same store
- WHEN imap's round closes without listing the member
- THEN imap drops it `Deleted`, the item is marked deleted and kept for jmap (vector 75), and jmap's next sync pushes the `Remove` (vector 76)

### Requirement: SYNC §4 and §5 Completeness binds
A connector MUST set `complete` only on a page of a round, MUST mark a page `last` only once its listing is exhausted, and MUST hand a cursor with every other page of a round. An engine MUST refuse a page that is neither `last` nor carrying a cursor, failing the run before that page's write, the round left open as the pages before it left it. A round MUST reconcile the placements in its scope alone.

#### Scenario: a page without a cursor
- GIVEN a round whose second page says it is not the last and hands no cursor
- WHEN the engine meets it
- THEN the run fails, the first page's write stands, the round stays open at its cursor and no member is dropped (vector 79)

## ADDED Requirements

### Requirement: SYNC §5 A mass absence parks
A round whose last page finds absent more than half of the based bindings of its source in its scope MUST NOT close when those number at least 20, unless the run carries `accept_absences`: it drops nothing, lands its last page as a page before the last with no cursor, writes no `CloseRound`, and the run reports the round parked with both counts. Nothing is stored but the open round; a later run lists it again from its first page and decides again.

#### Scenario: an empty listing of a full mailbox
- GIVEN 20 based bindings and a round answered by one empty last page
- WHEN the run reaches its close
- THEN nothing is dropped, the round stays open with no cursor and the run reports 20 absent of 20 (vector 77); with `accept_absences` the round closes and drops all 20 (vector 78)

### Requirement: SYNC §5 A server collection is deleted from an absence only when enabled
An engine mirroring collections between sources MUST NOT delete a collection on one source's server because another source no longer lists it unless its configuration enables it, and then only when that collection is empty or every member of it was reconciled in the same run.
