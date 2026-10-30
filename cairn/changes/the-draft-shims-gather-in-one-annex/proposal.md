---
cairn: change
id: the-draft-shims-gather-in-one-annex
status: draft
created: 2026-10-30
---

# The draft shims gather in one upgrade annex

## Why

Moved out of should-fix-before-the-freeze (2026-10-30). STORAGE carries sentences only reconciliation reads, each about a store an earlier draft wrote: "predating §15.6" in §15.6 and Annex B, "an earlier draft" in §13 (`level` 0, `round_band`), A.1 (a row written at `Meta` before marks), §6 (probes, `bindings.shared_object`). A reader of the frozen text should not meet them, and an implementation that never opened a draft store should not have to implement them.

## What

- An annex of STORAGE, read only by reconciliation (§6), listing each shim with the draft it serves; the sections it leaves state the current rule alone.
- Done once the last draft schema edit before storage-v1.0.0 has landed, since every such edit adds a shim.

## Lands in

The last storage draft before storage-v1.0.0.
