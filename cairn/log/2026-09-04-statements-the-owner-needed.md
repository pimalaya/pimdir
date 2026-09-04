---
cairn: log
change: statements-the-owner-needed
date: 2026-09-04
---

# The statements an owner needed and the document never named

The reference implementation carried sixteen statements of its own beside the canonical ones, and going through them found that thirteen serve rules this document states: the diff's reads of summaries and addresses by link id (`load_<kind>_summaries`, `load_addresses_by_link`), the binding drops (`delete_binding`, `delete_item_bindings`), the retained row a revive or a move purge acts on (`retained_item`), the origin a Created placement carries (`origin_for_link`), the move exception of §11 (`held_elsewhere`), the queued add's collision check (`live_item_for_link`), and two reads (`handle_for_link`, `list_item_bindings`). They are canonical now, named where the rule is.

Two canonical statements changed shape so the owner needs no read of its own: `cancel_action` returns the pin it releases, and `park_action` counts the attempt itself. The two the implementation kept for deleting a mail or contact summary were unreachable, a collection's kind being fixed, and went. What stays private is the operator tool's diagnostics.
