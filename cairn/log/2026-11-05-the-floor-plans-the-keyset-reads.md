---
cairn: log
change: the-floor-plans-the-keyset-reads
date: 2026-11-05
---

# The floor plans the keyset reads

checks/floor.sh now plans, on SQLite 3.18.2 built with the AOSP flags, the reads checks/invariants.sh plans on a current SQLite: list_mail_page_filtered, search_mail, search_contacts, search_calendar and search_files merging each collection's seek on `items_by_sort` beyond the cursor and scanning nothing; list_mail_page_desc, list_items_page_desc and the six oldest-first pages seeking their cursor; count_mail, count_mail_by_day and count_unread seeking their floor. The floor has neither `STRICT` nor the shell's `.parameter`, so the list parameters' table leaves `value` untyped, as the Android app's fork of `create_param` does, and each parameter is spelled as a literal. No rule moves: STORAGE §9.3 and §14.1 already state these plans; the floor, where the app runs the canonical reads verbatim, now holds them too.

Why (cairn/changes/performance-audit-2026-11-05, F10): `value` declared `ANY` outside a `STRICT` table takes NUMERIC affinity, and `x.collection = p.id` then stops seeking its collection. The check fails so: with `value ANY` in its param table, eight of its assertions fail (the five merged pages, the three counts' floor), and list_mail_page_filtered measured 203 ms at 100,000 messages against 0.4 ms. The sentence saying so in STORAGE §4.4 waits for storage-draft-09, the part being tagged.

Guarded by checks/floor.sh itself (`nix flake check`, the `floor` check).
