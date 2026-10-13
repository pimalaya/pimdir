---
cairn: delta
change: round-head
---

## ADDED Requirements

### Requirement: SYNC §2 Head
A head SHALL be one page, listed while a round is open, of what changed in the collection since the round began: a delta head lists from the round's checkpoint, a band head lists the members the source dates from the instant the round opened.

### Requirement: SYNC §4 Heads
A connector SHALL state which heads it lists. A delta head MUST carry the checkpoint the source holds now. A band head lists by an instant that never moves back, less a margin of two days, and carries no checkpoint and no vanished handle. A head never moves the round's cursor. A rejected head position MUST fail the head and name a restart. A connector listing band heads MUST list again, in every round's last page, read no earlier than that page's checkpoint, every member a band head would list then. A connector listing delta heads MUST read every page's members no earlier than the head before it.

#### Scenario: band relisting keeps a head's member
- GIVEN a band head named g3 and g4, unstamped, and the source has since removed g4
- WHEN the round's last page lists g3 again with the delta link
- THEN g3 is stamped and kept, and g4 is found absent (vector 66)

### Requirement: SYNC §5 Heads
A run resuming an open round SHOULD list its head before the round's next page, and MAY list one between pages, never between the last page and the close. The head is a delta head from the round's checkpoint, or a band round's from the source's checkpoint; else a band head from `round_started_at`; else none. It is checked against the run's scope and merged as a page before the last. A delta head stamps its members and records its checkpoint as the round's. A band head does neither. A head derives no `Add` and infers no delete. A rejected head position restarts the round over the run's scope.

#### Scenario: an arrival during an open round
- GIVEN a round opened at history id h1000, with cursor t1
- WHEN the head from h1000 lists a3 with checkpoint h1001, and the last page lists a0
- THEN a3 is named and stamped, it survives the close, and the round closes on h1001 (vector 62)

## MODIFIED Requirements

### Requirement: SYNC §5 Rounds
The round SHALL close on its last page's checkpoint when that page carries one, else on the latest a head or an earlier page landed, else keeping the old one. A band round's pages hand no checkpoint, but its heads do.

### Requirement: SYNC §5 Creates wait for the page that lands them
An `Add` MUST NOT be derived before the last page of an open round has landed, and a head's write is no exception.

### Requirement: SYNC §5 Candidates
The candidates of a page before the last, and of a head, SHALL be its members and vanished handles alone.

### Requirement: SYNC §10 The load and the write
A head SHALL load `Handles` of its members and `Links` of their hints. `SetRoundCursor` with no cursor keeps the cursor a page landed.

### Requirement: STORAGE §10 Coverage and rounds
A delta head SHALL stamp the handles it listed, and record its checkpoint with `set_round_cursor` and a `NULL` cursor, which keeps the cursor. A band head records neither.
