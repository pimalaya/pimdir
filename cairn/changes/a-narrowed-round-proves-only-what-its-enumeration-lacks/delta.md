---
cairn: delta
change: a-narrowed-round-proves-only-what-its-enumeration-lacks
---

## MODIFIED Requirements

### Requirement: SYNC §5 A narrowed listing proves only what its enumeration lacks
A round whose last page is `narrowed` MUST find absent only a member, in its scope, whose handle the `enumerated` list that page hands lacks; a member whose handle that list holds is never absent there, whatever its `date`. A narrowed round whose last page hands no `enumerated` MUST find no member absent: a removal is applied there only when the source states it, the round closes as any round does, and an engine SHOULD report the based bindings it left unlisted. `list_unstamped_bindings` answers `:narrowed = 0 OR (:enumerated = 1 AND the handle is not in the slot)`; `round_started_at` no longer decides an absence. Replaces: a narrowed round found absent any member dated before `round_started_at`, and an undated or later-dated one only when `enumerated` lacked it.

#### Scenario: a band narrowed by arrival and an old `Date` received late
- GIVEN a band [2025-11-01, 2026-10-16) narrowed by `before:` and `after:`, which read the arrival, and a bound message dated 2026-01-01 received in November, which the band's pages do not list and the last page's `enumerated` holds
- WHEN the last page lands
- THEN the message is kept, neither dropped nor pushed; a bound message of the band the enumeration lacks is dropped `Deleted` (vectors/sync/160)

#### Scenario: a `Date` ahead of its arrival
- GIVEN a scope [2026-09-01, open) narrowed by `receivedDateTime` from two days below `since`, and a bound message dated 1 October received on 20 August, unlisted and held by `enumerated`
- WHEN the last page lands
- THEN it is kept, as is an undated message the enumeration holds; a message dated 5 October the enumeration lacks is dropped (vectors/sync/161)

#### Scenario: a narrowed round handing no enumeration
- GIVEN a scope narrowed by `receivedDateTime` whose last page hands no `enumerated`, and three bound messages it did not list, undated, dated 2035 and dated 5 October
- WHEN the last page lands
- THEN none is dropped nor pushed and the round closes (vectors/sync/107, which dropped the third before)

#### Scenario: an enumeration lacking an undated member
- GIVEN a whole-scope round narrowed by `receivedDateTime` whose `enumerated` lacks an undated member and a dated one
- WHEN the last page lands
- THEN both are dropped (vectors/sync/47, unchanged)

#### Scenario: the statement
- GIVEN an open round over [2026-09-01, open), members dated 2026-10-06, undated and dated 2035, none stamped
- WHEN `list_unstamped_bindings` runs with `:narrowed` 1
- THEN it answers none with `:enumerated` 0, the two the slot lacks with `:enumerated` 1, and never the 2026-10-06 member while the slot holds it; over a band ending 2026-09-01, a member dated 2026-01-01 the slot holds is not answered (checks/invariants.sh, "narrowed: …")

### Requirement: SYNC §5 A narrowed listing says so
A filter on another instant than the `Date` lists no superset of a scope whatever its margin: it misses an undated member, one whose `Date` runs ahead of its arrival past its lower bound and one whose `Date` runs behind its arrival past its upper bound (a message appended, imported or delivered long after its `Date`). A connector offering an unfiltered enumeration SHOULD hand it on every narrowed round's last page, a band round's included. The margin of two days below `since` stays, so a received-date narrowing misses as little as it can.
