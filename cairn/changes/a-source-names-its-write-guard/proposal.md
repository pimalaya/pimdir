---
cairn: change
id: a-source-names-its-write-guard
status: draft
created: 2026-10-30
---

# A source names whether it enforces a write's precondition

## Why

The part of a-source-states-its-write-guard edit 7 of the pimdir stable-release plan left for later (2026-10-30): the general capability rule landed first (a-capability-added-later-is-read-where-stated) and the unguarded push window is stated (SYNC §4, a-merge-keeps-every-body), so the guard names can arrive after storage-v1.0.0 as capabilities added after the base set, read only where a row states them. The reasoning is that change's proposal.md.

## What

- Annex B.1: a guard capability per mutable kind (`contacts.card.guard`, `calendar.item.guard`, a file one if files sync), `full` when every update and remove is gated on the revision, `partial` with a detail when only some are, `none` when writes are unconditional; marked with the version adding them.
- SYNC §4 and §5: a connector declaring `none` claims no gated push; whether the engine re-reads a member's revision before an unguarded push is a MUST or the connector's.
- A producer MAY warn on an edit to an item held by an unguarded source.

## Open questions

- Whether the re-read before an unguarded push is a MUST (it narrows the window, it cannot close it) or left to the connector.
- Naming: one `*.guard` capability per kind, or one source-wide.

## Lands in

A STORAGE minor after storage-v1.0.0 (a capability added after the base set), with SYNC's.
