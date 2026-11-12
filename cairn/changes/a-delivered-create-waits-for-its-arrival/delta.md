---
cairn: delta
change: a-delivered-create-waits-for-its-arrival
---

## ADDED Requirements

### Requirement: SYNC §2, §5 A delivered create waits for its arrival
A pending create whose `Add` was accepted with no handle, or into which a relocation was accepted, SHALL be recorded delivered (`DeliverPlacement`, `deliver_binding`): its binding keeps the provisional handle and gains a base naming nothing. Until the page naming its member lands it, it MUST derive no change, no absence finds it and no run drops it; a `Remove` or a `Move` staged on it is held, then pushed against the listed handle.

#### Scenario: it derives nothing and no round finds it absent
- GIVEN a delivered create holding a staged `\Seen` and a delivered one tombstoned
- WHEN a delta lists another member
- THEN nothing is pushed or dropped (vectors/sync/136)

#### Scenario: a round landing it on no page
- GIVEN a live delivered create holding no body and a delivered tombstone
- WHEN a round closes listing another member
- THEN both keep waiting, nothing is dropped and the round closes (vectors/sync/139)

#### Scenario: a move staged on it lands with it
- GIVEN a delivered tombstone in Trash whose destination is a pending create in INBOX
- WHEN a delta names its member under 7
- THEN the relocation is pushed against 7 and the INBOX create is delivered in turn (vectors/sync/137)

#### Scenario: its staged flags push once it lands
- GIVEN a delivered create holding a staged `\Seen`
- WHEN a delta names its member unread under 7
- THEN `SetFlags` adds `\Seen` on 7 (vectors/sync/138)

## MODIFIED Requirements

### Requirement: SYNC §4 An add accepted without a handle
The engine MUST record the create delivered, its provisional binding, staged body and flags kept, no `Superseded` drop written and no `Created` reported (vectors/sync/92). An accepted relocation delivers the create its destination names (vectors/sync/20).

### Requirement: SYNC §3, STORAGE §10 Origins and absences read members
A binding under a provisional handle is no origin (`origin_for_link`) and is never found absent (`list_unstamped_bindings`) (checks/invariants.sh, "A delivered create is no member a listing names").

### Requirement: SYNC §3, §4 A delivered create stays a destination; a delete leaves one collection
`destination_for_link` names a pending create or a delivered one, so a delivery recorded before the relocation leaves keeps its tombstone relocating (checks/invariants.sh). A `Remove` naming no destination takes the member out of the collection its handle names alone; on a source naming one message by one id in several collections, a connector deletes it for good only where it is held nowhere else.
