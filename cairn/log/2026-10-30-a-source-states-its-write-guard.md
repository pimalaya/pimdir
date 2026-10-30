---
cairn: log
change: a-source-states-its-write-guard
date: 2026-10-30
---

# A source states its write guard: what is decided lands, the names wait

Edit 7 of the pimdir stable-release plan decided the general capability rule now and the write-guard names later. Both halves of what was decided have already landed under their own entries, and this one closes the change:

- **STORAGE §15.6, Annex B** (a-capability-added-later-is-read-where-stated): a capability added after the base set is read only where a row states it, so a guard name arriving after storage-v1.0.0 reads an older owner's declaration as stating nothing, never as `none`.
- **SYNC §4** (a-merge-keeps-every-body): the unguarded window of a source enforcing no precondition is stated.

The guard names (`contacts.card.guard`, `calendar.item.guard`), what a connector declaring `none` may claim, the re-read before an unguarded push and their vector moved to a-source-names-its-write-guard, a draft for a STORAGE minor after the freeze. No text changes here.
