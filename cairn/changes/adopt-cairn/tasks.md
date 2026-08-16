---
cairn: tasks
change: adopt-cairn
---

# Tasks

The one open task this repository carries. It is deliberately the only one: while the format is `draft` a landed change is tracked by its log entry alone, so there is no per-change checklist to keep here.

- [ ] **At the version 1 freeze, end the draft relaxation.** A change then carries `proposal.md` and `tasks.md` again, and `cairn/spec/` is reconsidered: the freeze is when a capability file stops competing with SPEC.md and starts being worth its own maintenance. Both rules live in [AGENTS.md](../../../AGENTS.md) and both are written as scoped to the draft, so ending them is an edit there plus the log entry that records it. The freeze also ends the in-place editing of migrations/0001_init.sql (SPEC.md §6), which is the signal to watch for.
