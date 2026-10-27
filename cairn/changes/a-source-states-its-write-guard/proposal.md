---
cairn: change
id: a-source-states-its-write-guard
status: draft
created: 2026-10-18
---

# A source states whether it enforces a write's precondition

## Why

Borrowed from an external engine: capabilities report constraints, not booleans, so an adapter refuses what it cannot honour instead of silently ignoring it.

Most of that is already here (Annex B, capabilities, 2026-10-03): a capability is `full`, `partial` with a `detail` saying what is missing, or `none` with a `detail` saying why; a producer's gate refuses before it enqueues, an owner parks what a source does not support, and a source declares every capability of its kinds, `none` included. A partial reply (`calendar.reply` without `TENTATIVE`, say) already fits `partial` and its detail.

One constraint has no name. An `Update` and a `Remove` are "gated on `if_match` where supported" (SYNC §4): a source that cannot gate a write on the revision overwrites a concurrent server edit, and nothing tells the producer or the engine that this source's writes are last-writer-wins. That is the case the conflict machinery exists for (a-conflict-never-hides-a-server-edit), defeated one layer below it.

## What

- Annex B.1: a guard capability per mutable kind (`contacts.card.guard`, `calendar.item.guard`, `file.guard` if files sync), `full` when every update and remove is gated on the revision, `partial` with a detail when only some are, `none` when writes are unconditional.
- SYNC §4: a connector to a source declaring `none` MUST NOT claim a gated push; SYNC §5: the engine, before pushing a content change to such a source, re-reads the member's revision in the same run and treats a moved one as a remote edit.
- A producer MAY warn on an edit to an item held by an unguarded source.

## Open questions

- Whether the re-read before an unguarded push is a MUST (it narrows the window, it cannot close it) or left to the connector.
- Naming: one `*.guard` capability per kind, or one source-wide.
