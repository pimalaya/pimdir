---
cairn: change
id: algorithm-audit-2026-09-04
status: landed
created: 2026-09-04
---

# The algorithm audit of 2026-09-04, and its ledger

## Why

On 2026-09-04 the five documents, both migrations, all 130 statements, every vector and every cairn entry were read cold by four independent readers, each asked for algorithmic weaknesses and unhandled edge cases and told to check the log before reporting. Their reports were crossed; what all four found is listed first below, and what one found and the others confirmed on reading is kept when a scenario shows it. Several findings were interactions between rules landed on different days, each correct alone, which is the pattern this ledger exists to end.

## What

Every finding has a line in tasks.md, closed by the log entry, vector or check that answered it, or open with the reason. The next audit reads that file before it reads anything else.

## Scope / non-goals

- No rule was changed here; the changes are the nine log entries of 2026-09-05 this folder points at.
- Items left open are decisions, not repairs, and each says what would decide it.
