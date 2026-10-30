---
cairn: log
change: an-unbound-edit-was-already-fenced
date: 2026-10-30
---

# An unbound edit was already fenced

Correction to 2026-10-30-store-gaps-io-pimdir-found, which listed io-pimdir's `apply_unbound` as applying a queued `update` without checking `if_match`. It does not: io-pimdir's drain checks the fence in `stage_action` before it finds the item unbound, so a guarded `update` of an item no source binds parks on a replaced body, as STORAGE §15.3 states. io-pimdir's tests/unbound_items.rs `an_unbound_edit_over_a_replaced_body_parks` pins it, and passed before any change. No rule moved.
