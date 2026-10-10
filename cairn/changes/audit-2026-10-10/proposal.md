---
cairn: change
id: audit-2026-10-10
status: active
created: 2026-10-10
---

# The differential audit of 2026-10-10, and its ledger

## Why

Five changes landed on 2026-10-10 (mail-reads-take-a-floor, bodies-released-below-a-date, item-references, the-file-kind, automatic-references), each guarded by its own scenarios. Past defects were mostly interactions between rules landed on different days, so this audit read those five entries against the older rules they touch: retention and `held_elsewhere`, `collect_before`, the scope's treatment of undated mail, writer-derived keys and `seq`, §6 reconciliation, the planner-without-statistics assumption of §9.3, and the checks each log entry claims.

## What

Every finding has one line in tasks.md with a severity and a pointer, open until a log entry, vector or check answers it. The open items of every earlier tasks.md were read first and none is repeated. "Confirmed" means reproduced with the canonical schema and statements on a scratch store (SQLite 3.53.3, foreign keys on, no `ANALYZE`) or read directly off the normative text and io-pimdir's code; "plausible" means the reasoning holds but no scenario was run end to end.

The check gaps were found by mutation: each predicate of the new statements and triggers was removed in a scratch copy and checks/invariants.sh run against it. A surviving mutant is a rule with no failing check (AGENTS.md §4). Mutants equivalent under the schema (the `email` role filter, implied by the card kind join; `release_bases_before`'s own-body test, implied by the local-edit exclusion) are not listed.

## Scope / non-goals

- Nothing normative, no statement, no check and no io-pimdir file was changed; the fixes are proposed one line each in tasks.md.
- `recursive_triggers` was checked: the whole of invariants.sh passes with it on, as the-file-kind entry claims.
- The SQLite floor was checked: the new statements need `UPDATE … FROM` (3.33, `release_bases_before`) and `RETURNING` (3.35), both under the 3.37 STORAGE §4.1 and the schema header already state for `STRICT`; the floor stays 3.37.
